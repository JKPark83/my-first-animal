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
local plotSignLabels: { TextLabel } = {}
local assignedPlot: { [number]: number } = {} -- userId -> plot index
local plotOwner: { [number]: number? } = {} -- plot index -> userId

local builtSpawn: SpawnLocation? = nil
local builtShopPad: BasePart? = nil
local builtShopTeleport: CFrame? = nil -- 가게로 빠른 이동 시 도착 지점(가게 패드 위, 가게를 바라봄)
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

	-- 이름 간판 (북쪽 출입구 위)
	local signPost = part({
		Name = "SignPost",
		Size = Vector3.new(8, 3, 0.6),
		Position = Vector3.new(centerX, FARM.fenceHeight + 2, centerZ - PLOT / 2),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(90, 64, 40),
	}, folder)
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.fromScale(10, 3)
	signGui.StudsOffset = Vector3.new(0, 2, 0)
	signGui.AlwaysOnTop = false
	signGui.MaxDistance = 220
	signGui.Parent = signPost
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "🌿 빈 농장"
	signLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signLabel.TextStrokeTransparency = 0.4
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.Parent = signGui
	plotSignLabels[index] = signLabel

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
				plotSignLabels[i].Text = "🌿 " .. player.Name .. " 의 농장"
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
			plotSignLabels[i].Text = "🌿 빈 농장"
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
