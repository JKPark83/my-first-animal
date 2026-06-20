--!strict
--[[
	FarmBuilder
	------------
	플레이어가 노는 3D 월드를 코드로 생성합니다(참고: my-first-cargame 의 LoungeBuilder).
	- 중앙 허브(바닥 + 스폰)
	- 알파카 가게 건물 + 가게 패드(밟으면 상점 열림 신호)
	- 개인 농장 구역 N개(울타리 + 슬롯 배치 + 이름 간판 + 알파카 폴더)
	- 글로벌 순위 전광판

	월드는 서버 시작 시 한 번 생성되고, 농장 구역은 접속 순서대로 플레이어에게 배정됩니다.

	좌표: 허브 = 원점. 가게 = -Z(북). 개인 농장들 = +Z(남)에 한 줄로 배치.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local FarmBuilder = {}

local FARM = GameConfig.Farm
local PLOT = FARM.plotSize
local GAP = FARM.plotGap
local FLOOR_TOP = 0.6 -- 농장 바닥 윗면 y (알파카가 서는 높이)

export type PlotInfo = {
	index: number,
	origin: Vector3, -- 농장 중심(바닥 윗면 기준 y=FLOOR_TOP)
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }, -- 배회 가능 영역(울타리 안쪽)
	slotCFrames: { CFrame }, -- 슬롯 위치(바닥 윗면, 알파카가 허브를 바라보게)
	spawnCFrame: CFrame, -- 이 농장에 들어올 때 플레이어 스폰 위치
	folder: Folder,
	alpacasFolder: Folder,
}

local plots: { PlotInfo } = {}
local plotSignLabels: { { TextLabel } } = {} -- 농장별 간판 라벨들(앞/뒤 면 SurfaceGui)
local assignedPlot: { [number]: number } = {} -- userId -> plot index
local plotOwner: { [number]: number? } = {} -- plot index -> userId

local builtSpawn: SpawnLocation? = nil
local builtShopPad: BasePart? = nil
local builtShopTeleport: CFrame? = nil -- 가게로 빠른 이동 시 도착 지점(가게 패드 위, 가게를 바라봄)
local builtFoodPad: BasePart? = nil -- 먹이 상점 패드(밟으면 먹이 상점 열림)
local builtFoodTeleport: CFrame? = nil -- 먹이 상점으로 빠른 이동 도착 지점
local builtAccessoryPad: BasePart? = nil -- 악세사리 가게 패드(밟으면 악세사리 가게 열림)
local builtAccessoryTeleport: CFrame? = nil -- 악세사리 가게로 빠른 이동 도착 지점
local builtGaragePad: BasePart? = nil -- 밟으면 카트가 소환되는 차고 패드
local builtKartSpawn: CFrame? = nil -- 카트 소환 위치(차고 패드 위, 농장 방향)
local leaderboardLabel: TextLabel? = nil

-- =====================================================================
-- 파트 생성 헬퍼
-- =====================================================================
local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- 보조 상점(먹이/악세사리) 건물 + 입장 패드를 만든다.
-- 알파카 가게와 같은 구조를 약간 작게 만들며, 패드(밟으면 열림)와 텔레포트 도착 CFrame 을 반환한다.
local function buildSideShop(
	parent: Instance,
	folderName: string,
	center: Vector3,
	signText: string,
	roofColor: Color3,
	padText: string,
	padColor: Color3
): (BasePart, CFrame)
	local f = Instance.new("Folder")
	f.Name = folderName
	f.Parent = parent

	part({
		Name = "Floor",
		Size = Vector3.new(36, 1, 24),
		Position = center + Vector3.new(0, 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(210, 180, 140),
	}, f)
	part({
		Name = "BackWall",
		Size = Vector3.new(36, 14, 1),
		Position = center + Vector3.new(0, 7, -11.5),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(245, 230, 210),
	}, f)
	for _, sx in ipairs({ -1, 1 }) do
		part({
			Name = "SideWall",
			Size = Vector3.new(1, 14, 24),
			Position = center + Vector3.new(sx * 18, 7, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(245, 230, 210),
		}, f)
	end
	part({
		Name = "Roof",
		Size = Vector3.new(42, 1.5, 30),
		Position = center + Vector3.new(0, 14.5, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = roofColor,
	}, f)

	-- 간판
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.fromScale(14, 3.6)
	signGui.StudsOffset = Vector3.new(0, 4, 0)
	signGui.AlwaysOnTop = false
	signGui.Parent = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		Position = center + Vector3.new(0, 16, 0),
	}, f)
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = signText
	signLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.Parent = signGui

	-- 입장 패드(밟으면 해당 상점 열림) — 건물 앞(+Z, 허브 방향)
	local pad = part({
		Name = "Pad",
		Size = Vector3.new(18, 1, 11),
		Position = center + Vector3.new(0, 1.1, 18),
		Material = Enum.Material.Neon,
		Color = padColor,
	}, f)
	-- 텔레포트 도착 지점: 패드 위(기본 lookVector -Z → 건물 방향)
	local teleCF = CFrame.new(pad.Position + Vector3.new(0, 3, 0))

	local padGui = Instance.new("BillboardGui")
	padGui.Size = UDim2.fromScale(9, 2.4)
	padGui.StudsOffset = Vector3.new(0, 4, 0)
	padGui.AlwaysOnTop = true
	padGui.MaxDistance = 80
	padGui.Parent = pad
	local padLabel = Instance.new("TextLabel")
	padLabel.Size = UDim2.fromScale(1, 1)
	padLabel.BackgroundTransparency = 1
	padLabel.Text = padText
	padLabel.TextColor3 = Color3.fromRGB(80, 50, 20)
	padLabel.Font = Enum.Font.FredokaOne
	padLabel.TextScaled = true
	padLabel.Parent = padGui

	return pad, teleCF
end

-- 슬롯 배치 CFrame 계산: 농장 중심 기준 slotCols x slotRows 그리드
local function computeSlotCFrames(centerX: number, centerZ: number): { CFrame }
	local cols = FARM.slotCols
	local rows = FARM.slotRows
	local usable = PLOT - 14 -- 울타리 안쪽 여백
	local stepX = usable / cols
	local stepZ = usable / rows
	local startX = centerX - usable / 2 + stepX / 2
	local startZ = centerZ - usable / 2 + stepZ / 2
	local result: { CFrame } = {}
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x = startX + c * stepX
			local z = startZ + r * stepZ
			-- 알파카가 허브(-Z) 방향을 보도록
			result[#result + 1] = CFrame.new(Vector3.new(x, FLOOR_TOP, z), Vector3.new(x, FLOOR_TOP, z - 1))
		end
	end
	return result
end

-- 울타리: 둘레에 기둥 + 가로 레일. 북쪽(-Z, 허브 방향)에 출입구 간격을 둠.
local function buildFence(folder: Folder, centerX: number, centerZ: number)
	local half = PLOT / 2
	local postColor = Color3.fromRGB(150, 110, 70)
	local railColor = Color3.fromRGB(176, 134, 92)
	local h = FARM.fenceHeight
	local spacing = 6
	local gateHalf = 7 -- 출입구 절반 폭

	local function postAt(x: number, z: number)
		part({
			Name = "FencePost",
			Size = Vector3.new(1.2, h, 1.2),
			Position = Vector3.new(x, h / 2, z),
			Material = Enum.Material.WoodPlanks,
			Color = postColor,
		}, folder)
	end

	local function rail(x: number, z: number, sizeX: number, sizeZ: number, y: number)
		part({
			Name = "FenceRail",
			Size = Vector3.new(sizeX, 0.5, sizeZ),
			Position = Vector3.new(x, y, z),
			Material = Enum.Material.WoodPlanks,
			Color = railColor,
		}, folder)
	end

	-- 남/동/서 변: 연속 레일 + 기둥. 북변(-Z): 출입구 간격.
	-- 동/서 변 (Z축 따라)
	for _, sx in ipairs({ -1, 1 }) do
		local x = centerX + sx * half
		rail(x, centerZ, 0.6, PLOT, h - 1)
		rail(x, centerZ, 0.6, PLOT, h * 0.45)
		local z = centerZ - half
		while z <= centerZ + half do
			postAt(x, z)
			z += spacing
		end
	end
	-- 남변 (+Z, 멀리)
	do
		local z = centerZ + half
		rail(centerX, z, PLOT, 0.6, h - 1)
		rail(centerX, z, PLOT, 0.6, h * 0.45)
		local x = centerX - half
		while x <= centerX + half do
			postAt(x, z)
			x += spacing
		end
	end
	-- 북변 (-Z, 허브 방향) — 가운데 출입구
	do
		local z = centerZ - half
		local sideLen = half - gateHalf
		-- 좌측 레일
		rail(centerX - gateHalf - sideLen / 2, z, sideLen, 0.6, h - 1)
		rail(centerX - gateHalf - sideLen / 2, z, sideLen, 0.6, h * 0.45)
		-- 우측 레일
		rail(centerX + gateHalf + sideLen / 2, z, sideLen, 0.6, h - 1)
		rail(centerX + gateHalf + sideLen / 2, z, sideLen, 0.6, h * 0.45)
		-- 기둥(출입구 양옆 + 모서리)
		postAt(centerX - half, z)
		postAt(centerX + half, z)
		postAt(centerX - gateHalf, z)
		postAt(centerX + gateHalf, z)
	end
end

-- 개인 농장 구역 한 칸 생성
local function buildPlot(index: number, centerX: number, centerZ: number): PlotInfo
	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. index

	-- 잔디 바닥
	part({
		Name = "PlotFloor",
		Size = Vector3.new(PLOT, 1.2, PLOT),
		Position = Vector3.new(centerX, FLOOR_TOP - 0.6, centerZ),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(120, 184, 96),
	}, folder)

	buildFence(folder, centerX, centerZ)

	-- 이름 간판: 글자를 나무 판 면에 직접 인쇄(SurfaceGui)해 가림 현상 해소.
	-- (기존: 떠 있는 BillboardGui 가 나무 판에 가려 안 보였음)
	-- 출입구 양옆 게이트 기둥(±gateHalf=±7, 높이 fenceHeight) 위에 판을 얹는다.
	-- → 새 기둥을 만들지 않아 울타리/게이트 기둥과 겹치지 않음.
	local signZ = centerZ - PLOT / 2
	local signWidth = 15 -- 게이트 기둥(±7)을 덮는 폭
	local signHeight = 3.4
	-- 간판 판: 게이트 기둥 윗면(y=fenceHeight) 바로 위 0.1 띄워 얹음
	-- (정확히 0 으로 맞추면 판 바닥면과 기둥 윗면이 동일 평면 → z-fighting. 0.1 틈은 거리상 안 보임)
	local signBoard = part({
		Name = "SignBoard",
		Size = Vector3.new(signWidth, signHeight, 0.6),
		Position = Vector3.new(centerX, FARM.fenceHeight + 0.1 + signHeight / 2, signZ),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(96, 66, 40),
	}, folder)
	-- 앞(허브 방향 -Z = Front) / 뒤(농장 안쪽 +Z = Back) 면에 글자 인쇄
	local labels: { TextLabel } = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.CanvasSize = Vector2.new(560, 130)
		sg.Parent = signBoard
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = "🌿 빈 농장"
		lbl.TextColor3 = Color3.fromRGB(255, 248, 224)
		lbl.TextStrokeTransparency = 0.4
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.Parent = sg
		labels[#labels + 1] = lbl
	end
	plotSignLabels[index] = labels

	-- 알파카 폴더
	local alpacasFolder = Instance.new("Folder")
	alpacasFolder.Name = "Alpacas"
	alpacasFolder.Parent = folder

	folder.Parent = workspace:FindFirstChild("AlpacaFarm") :: Instance

	local inset = 8
	return {
		index = index,
		origin = Vector3.new(centerX, FLOOR_TOP, centerZ),
		bounds = {
			minX = centerX - PLOT / 2 + inset,
			maxX = centerX + PLOT / 2 - inset,
			minZ = centerZ - PLOT / 2 + inset,
			maxZ = centerZ + PLOT / 2 - inset,
		},
		slotCFrames = computeSlotCFrames(centerX, centerZ),
		-- 출입구 안쪽에서 농장을 바라보며 스폰
		spawnCFrame = CFrame.new(Vector3.new(centerX, FLOOR_TOP + 3, centerZ - PLOT / 2 + 6)),
		folder = folder,
		alpacasFolder = alpacasFolder,
	}
end

-- =====================================================================
-- 빌드
-- =====================================================================
function FarmBuilder.build(): Folder
	local existing = workspace:FindFirstChild("AlpacaFarm")
	if existing then
		return existing :: Folder
	end

	local root = Instance.new("Folder")
	root.Name = "AlpacaFarm"
	root.Parent = workspace

	-- 전체 지면(흙길)
	local totalWidth = FARM.maxFarms * (PLOT + GAP) + 200
	part({
		Name = "Ground",
		Size = Vector3.new(totalWidth, 2, 460),
		Position = Vector3.new(0, -1, 60),
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(150, 130, 100),
	}, root)

	-- 중앙 허브 바닥(나무 데크)
	part({
		Name = "HubFloor",
		Size = Vector3.new(80, 1.5, 70),
		Position = Vector3.new(0, 0.2, -10),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(196, 162, 120),
	}, root)

	-- 스폰
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 1.2, 0)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(160, 220, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	builtSpawn = spawn

	-- 알파카 가게 건물 (-Z, 북쪽)
	local shopFolder = Instance.new("Folder")
	shopFolder.Name = "Shop"
	shopFolder.Parent = root
	local shopCenter = Vector3.new(0, 0, -52)
	part({
		Name = "ShopFloor",
		Size = Vector3.new(44, 1, 28),
		Position = shopCenter + Vector3.new(0, 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(210, 180, 140),
	}, shopFolder)
	-- 벽 + 지붕
	part({
		Name = "ShopBackWall",
		Size = Vector3.new(44, 16, 1),
		Position = shopCenter + Vector3.new(0, 8, -13.5),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(245, 230, 210),
	}, shopFolder)
	for _, sx in ipairs({ -1, 1 }) do
		part({
			Name = "ShopSideWall",
			Size = Vector3.new(1, 16, 28),
			Position = shopCenter + Vector3.new(sx * 22, 8, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(245, 230, 210),
		}, shopFolder)
	end
	part({
		Name = "ShopRoof",
		Size = Vector3.new(50, 1.5, 34),
		Position = shopCenter + Vector3.new(0, 16.5, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(210, 110, 90),
	}, shopFolder)
	-- 간판
	local shopSignGui = Instance.new("BillboardGui")
	shopSignGui.Size = UDim2.fromScale(16, 4)
	shopSignGui.StudsOffset = Vector3.new(0, 4, 0)
	shopSignGui.AlwaysOnTop = false
	shopSignGui.Parent = part({
		Name = "ShopSign",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		Position = shopCenter + Vector3.new(0, 18, 0),
	}, shopFolder)
	local shopSignLabel = Instance.new("TextLabel")
	shopSignLabel.Size = UDim2.fromScale(1, 1)
	shopSignLabel.BackgroundTransparency = 1
	shopSignLabel.Text = "🦙 알파카 가게"
	shopSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopSignLabel.TextStrokeTransparency = 0.3
	shopSignLabel.Font = Enum.Font.FredokaOne
	shopSignLabel.TextScaled = true
	shopSignLabel.Parent = shopSignGui

	-- 가게 패드(밟으면 상점 열기) — 가게 앞
	local pad = part({
		Name = "ShopPad",
		Size = Vector3.new(20, 1, 12),
		Position = shopCenter + Vector3.new(0, 1.1, 20),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 210, 120),
	}, shopFolder)
	pad.Anchored = true
	builtShopPad = pad
	-- 가게로 빠른 이동 도착 지점: 패드 위에 서서 가게(-Z)를 바라봄.
	-- (기본 CFrame 의 lookVector 가 -Z 라 회전 없이도 가게 방향을 향함)
	builtShopTeleport = CFrame.new(pad.Position + Vector3.new(0, 3, 0))
	local padGui = Instance.new("BillboardGui")
	padGui.Size = UDim2.fromScale(8, 2.4)
	padGui.StudsOffset = Vector3.new(0, 4, 0)
	padGui.AlwaysOnTop = true
	padGui.MaxDistance = 80
	padGui.Parent = pad
	local padLabel = Instance.new("TextLabel")
	padLabel.Size = UDim2.fromScale(1, 1)
	padLabel.BackgroundTransparency = 1
	padLabel.Text = "🛒 가게 입장"
	padLabel.TextColor3 = Color3.fromRGB(80, 50, 20)
	padLabel.Font = Enum.Font.FredokaOne
	padLabel.TextScaled = true
	padLabel.Parent = padGui

	-- 먹이 상점(알파카 가게 왼쪽, -X) / 악세사리 가게(오른쪽, +X)
	local foodPad, foodTele = buildSideShop(
		root,
		"FoodShop",
		Vector3.new(-64, 0, -44),
		"🍽️ 먹이 상점",
		Color3.fromRGB(120, 180, 90),
		"🍽️ 먹이 상점",
		Color3.fromRGB(170, 230, 130)
	)
	builtFoodPad = foodPad
	builtFoodTeleport = foodTele

	local accPad, accTele = buildSideShop(
		root,
		"AccessoryShop",
		Vector3.new(64, 0, -44),
		"🎀 악세사리 가게",
		Color3.fromRGB(210, 120, 180),
		"🎀 악세사리 가게",
		Color3.fromRGB(245, 180, 220)
	)
	builtAccessoryPad = accPad
	builtAccessoryTeleport = accTele

	-- 글로벌 순위 전광판 (허브 동쪽)
	local board = part({
		Name = "LeaderboardBoard",
		Size = Vector3.new(1, 26, 36),
		Position = Vector3.new(48, 13, -10),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(28, 24, 36),
	}, root)
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Left
	boardGui.CanvasSize = Vector2.new(360, 280)
	boardGui.Parent = board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 48)
	title.BackgroundTransparency = 1
	title.Text = "🏆 농장 부자 순위"
	title.TextColor3 = Color3.fromRGB(245, 220, 90)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = boardGui
	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -20, 1, -58)
	body.Position = UDim2.new(0, 10, 0, 54)
	body.BackgroundTransparency = 1
	body.Text = "순위를 불러오는 중..."
	body.TextColor3 = Color3.fromRGB(230, 235, 245)
	body.Font = Enum.Font.GothamMedium
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextSize = 20
	body.Parent = boardGui
	leaderboardLabel = body

	-- =====================================================================
	-- 도로망 + 가로 풍경 (허브 ↔ 농장 연결, 차량 주행용)
	-- =====================================================================
	local roadsFolder = Instance.new("Folder")
	roadsFolder.Name = "Roads"
	roadsFolder.Parent = root

	local ROAD_Y = 0.15 -- 흙 바닥(윗면 y=0) 위에 살짝 얹힘
	local function road(cx: number, cz: number, sx: number, sz: number)
		part({
			Name = "Road",
			Size = Vector3.new(sx, 0.5, sz),
			Position = Vector3.new(cx, ROAD_Y, cz),
			Material = Enum.Material.Asphalt,
			Color = Color3.fromRGB(66, 68, 74),
		}, roadsFolder)
	end
	local function sidewalk(cx: number, cz: number, sx: number, sz: number)
		part({
			Name = "Sidewalk",
			Size = Vector3.new(sx, 0.6, sz),
			Position = Vector3.new(cx, ROAD_Y + 0.05, cz),
			Material = Enum.Material.Concrete,
			Color = Color3.fromRGB(205, 200, 188),
		}, roadsFolder)
	end
	local function dash(cx: number, cz: number, sx: number, sz: number)
		part({
			Name = "LaneMark",
			Size = Vector3.new(sx, 0.6, sz),
			Position = Vector3.new(cx, ROAD_Y + 0.08, cz),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(245, 226, 96),
		}, roadsFolder)
	end
	local function lamp(cx: number, cz: number)
		part({
			Name = "LampPost",
			Size = Vector3.new(0.6, 9, 0.6),
			Position = Vector3.new(cx, 4.6, cz),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(58, 60, 68),
		}, roadsFolder)
		local head = part({
			Name = "LampHead",
			Size = Vector3.new(1.8, 0.8, 1.8),
			Position = Vector3.new(cx, 9.3, cz),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 236, 170),
		}, roadsFolder)
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 236, 170)
		pl.Range = 24
		pl.Brightness = 1.4
		pl.Parent = head
	end
	local function tree(cx: number, cz: number)
		part({
			Name = "TreeTrunk",
			Size = Vector3.new(2, 7, 2),
			Position = Vector3.new(cx, 3.5, cz),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(112, 80, 48),
		}, roadsFolder)
		part({
			Name = "TreeLeaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(11, 11, 11),
			Position = Vector3.new(cx, 9.5, cz),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(86, 158, 74),
		}, roadsFolder)
	end

	-- 중앙 대로 (허브 → 농장, +Z 방향)
	road(0, 67, 20, 92) -- z ≈ 21 ~ 113 (허브 남쪽 가장자리에서 농장 앞까지)
	for z = 28, 106, 12 do
		dash(0, z, 1.4, 5)
	end
	sidewalk(-11.5, 67, 3, 92)
	sidewalk(11.5, 67, 3, 92)

	-- 농장 앞 가로 도로 (모든 농장 입구를 잇는 동서 도로)
	local frontZ = 113
	road(0, frontZ, 640, 16)
	for x = -300, 300, 16 do
		dash(x, frontZ, 5, 1.4)
	end
	sidewalk(0, frontZ - 9.2, 640, 2.5)

	-- 가로등 (대로 양옆)
	for z = 24, 108, 28 do
		lamp(-13.5, z)
		lamp(13.5, z)
	end

	-- 가로수 (빈 흙 공간 채우기)
	tree(-34, 44)
	tree(34, 60)
	tree(-34, 88)
	tree(34, 30)
	tree(-60, 70)
	tree(60, 96)

	-- 허브 데크(윗면 y=0.95) ↔ 중앙 대로(윗면 y=0.40) 경사로.
	-- 데크와 도로 사이 0.55 턱을 완만한 램프로 메워 카트가 걸리지 않게 한다.
	-- 윗면: 북쪽 끝(z≈23, 데크 옆) 0.95 → 남쪽 끝(z≈35, 도로) 0.40 (약 2.6° 경사)
	local ramp = part({
		Name = "HubRamp",
		Size = Vector3.new(22, 0.6, 12),
		Position = Vector3.new(0, 0.375, 29),
		Material = Enum.Material.Asphalt,
		Color = Color3.fromRGB(72, 74, 80),
	}, roadsFolder)
	ramp.CFrame = CFrame.new(ramp.Position) * CFrame.Angles(math.rad(2.6), 0, 0)

	-- 차고 패드(밟으면 카트 소환) — 허브 데크 위(스폰 바로 남쪽)
	-- 윗면 y=1.1 로 데크 윗면(0.95)보다 살짝 높여 z-fighting 방지(턱 0.15 — 주행 무시 가능)
	local garagePad = part({
		Name = "GaragePad",
		Size = Vector3.new(14, 1, 14),
		Position = Vector3.new(0, 0.6, 18),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(140, 220, 150),
	}, root)
	builtGaragePad = garagePad
	-- 카트 소환 위치: 패드 위, 농장 쪽(+Z)을 바라봄 (기본 LookVector -Z 라 180° 회전)
	builtKartSpawn = CFrame.new(garagePad.Position + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(180), 0)
	local garageGui = Instance.new("BillboardGui")
	garageGui.Size = UDim2.fromScale(8, 2.6)
	garageGui.StudsOffset = Vector3.new(0, 4, 0)
	garageGui.AlwaysOnTop = true
	garageGui.MaxDistance = 90
	garageGui.Parent = garagePad
	local garageLabel = Instance.new("TextLabel")
	garageLabel.Size = UDim2.fromScale(1, 1)
	garageLabel.BackgroundTransparency = 1
	garageLabel.Text = "🛺 카트 타기"
	garageLabel.TextColor3 = Color3.fromRGB(20, 70, 30)
	garageLabel.Font = Enum.Font.FredokaOne
	garageLabel.TextScaled = true
	garageLabel.Parent = garageGui

	-- 개인 농장 구역들 (+Z 남쪽 한 줄)
	local plotZ = 150
	for i = 1, FARM.maxFarms do
		local centerX = (i - (FARM.maxFarms + 1) / 2) * (PLOT + GAP)
		plots[i] = buildPlot(i, centerX, plotZ)
		plotOwner[i] = nil
	end

	return root
end

-- =====================================================================
-- 농장 배정 / 조회
-- =====================================================================
function FarmBuilder.getSpawnCFrame(): CFrame
	if builtSpawn then
		return builtSpawn.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 6, 0)
end

function FarmBuilder.getShopPad(): BasePart?
	return builtShopPad
end

-- 가게로 빠른 이동 시 도착 CFrame (가게 패드 위). 빌드 전이면 nil.
function FarmBuilder.getShopTeleportCFrame(): CFrame?
	return builtShopTeleport
end

-- 먹이 상점 패드 / 텔레포트 도착 CFrame. 빌드 전이면 nil.
function FarmBuilder.getFoodPad(): BasePart?
	return builtFoodPad
end
function FarmBuilder.getFoodTeleportCFrame(): CFrame?
	return builtFoodTeleport
end

-- 악세사리 가게 패드 / 텔레포트 도착 CFrame. 빌드 전이면 nil.
function FarmBuilder.getAccessoryPad(): BasePart?
	return builtAccessoryPad
end
function FarmBuilder.getAccessoryTeleportCFrame(): CFrame?
	return builtAccessoryTeleport
end

-- 카트 차고 패드 (밟으면 카트 소환). 빌드 전이면 nil.
function FarmBuilder.getGaragePad(): BasePart?
	return builtGaragePad
end

-- 카트 소환 CFrame (차고 패드 위). 빌드 전이면 nil.
function FarmBuilder.getKartSpawnCFrame(): CFrame?
	return builtKartSpawn
end

-- 빈 농장을 배정하고 인덱스 반환. 없으면 nil.
function FarmBuilder.assignPlot(player: Player): number?
	if assignedPlot[player.UserId] then
		return assignedPlot[player.UserId]
	end
	for i = 1, FARM.maxFarms do
		if plotOwner[i] == nil then
			plotOwner[i] = player.UserId
			assignedPlot[player.UserId] = i
			if plotSignLabels[i] then
				for _, lbl in ipairs(plotSignLabels[i]) do
					lbl.Text = "🌿 " .. player.Name .. " 의 농장"
				end
			end
			return i
		end
	end
	return nil
end

function FarmBuilder.releasePlot(player: Player)
	local i = assignedPlot[player.UserId]
	if i then
		plotOwner[i] = nil
		assignedPlot[player.UserId] = nil
		if plotSignLabels[i] then
			for _, lbl in ipairs(plotSignLabels[i]) do
				lbl.Text = "🌿 빈 농장"
			end
		end
		-- 남은 알파카 정리
		local plot = plots[i]
		if plot then
			for _, child in ipairs(plot.alpacasFolder:GetChildren()) do
				child:Destroy()
			end
		end
	end
end

function FarmBuilder.getPlotInfo(player: Player): PlotInfo?
	local i = assignedPlot[player.UserId]
	if not i then
		return nil
	end
	return plots[i]
end

-- 전광판 텍스트 갱신 (Main 의 주기 루프에서 호출)
function FarmBuilder.updateLeaderboard(entries: { { rank: number, name: string, worth: number } })
	if not leaderboardLabel then
		return
	end
	if #entries == 0 then
		leaderboardLabel.Text = "아직 순위가 없습니다.\n첫 부자가 되어보세요!"
		return
	end
	local function fmtMoney(n: number): string
		if n >= 1000000 then
			return ("%.1f백만"):format(n / 1000000)
		elseif n >= 1000 then
			return ("%.1f천"):format(n / 1000)
		end
		return tostring(n)
	end
	local lines = {}
	for _, e in ipairs(entries) do
		local medal = e.rank == 1 and "🥇" or (e.rank == 2 and "🥈" or (e.rank == 3 and "🥉" or (" " .. e.rank .. ".")))
		lines[#lines + 1] = ("%s  %-10s  $%s"):format(medal, string.sub(e.name, 1, 10), fmtMoney(e.worth))
	end
	leaderboardLabel.Text = table.concat(lines, "\n")
end

return FarmBuilder
