--!strict
--[[
	UIController (클라이언트)
	──────────────────────────────────────────────────────────────────────
	알파카 농장의 메인 HUD 및 상점 / 도감 / 순위 패널과 토스트 알림을
	코드로 생성하고 관리합니다.

	담당 범위:
	  - 상단 HUD     : 머니 / 슬롯 현황 / 도감 진도 + 우상단 버튼(상점·도감·순위·양털수집)
	  - 상점 패널    : 머니 알파카 카드 목록, 로벅스 알파카 안내, 슬롯 확장, 황금 갈퀴 게임패스
	  - 도감 패널    : 보유/미보유 알파카 그리드 (countInDex 종만)
	  - 순위 패널    : 글로벌 총자산 순위 + 내 총자산
	  - 토스트 알림  : 서버 Notify · 양털 수집 결과

	담당하지 않는 것:
	  - 케어 버튼(하단) / 알파카 머리 위 게이지 → CareController 담당
	  - CareFeedback 이벤트 처리              → CareController 담당
	──────────────────────────────────────────────────────────────────────
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes    = require(ReplicatedStorage:WaitForChild("Remotes"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 플레이어 데이터 캐시 (PlayerDataUpdated / GetPlayerData 로 갱신)
local data: any = nil

-- ======================================================================
-- 헬퍼 함수
-- ======================================================================

-- 인스턴스 생성 (props 테이블을 그대로 속성에 대입)
local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- UICorner 추가
local function corner(radius: number, target: Instance)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, target)
end

-- Frame 생성 헬퍼 (기본값 + 오버라이드)
local function makeFrame(props: { [string]: any }, parent: Instance?): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel  = 0,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return make("Frame", defaults, parent) :: Frame
end

-- TextLabel 생성 헬퍼
local function makeLabel(text: string, props: { [string]: any }?, parent: Instance?): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Text                   = text,
		TextColor3             = Color3.fromRGB(60, 40, 20),
		Font                   = Enum.Font.GothamMedium,
		TextScaled             = true,
	}
	if props then
		for k, v in pairs(props) do
			defaults[k] = v
		end
	end
	return make("TextLabel", defaults, parent) :: TextLabel
end

-- TextButton 생성 헬퍼
local function makeButton(text: string, color: Color3, props: { [string]: any }?, parent: Instance?): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = color,
		Text             = text,
		TextColor3       = Color3.fromRGB(255, 255, 255),
		Font             = Enum.Font.GothamBold,
		TextScaled       = true,
		AutoButtonColor  = true,
	}
	if props then
		for k, v in pairs(props) do
			defaults[k] = v
		end
	end
	return make("TextButton", defaults, parent) :: TextButton
end

-- 숫자 콤마 포맷: 12345 → "12,345"
local function formatMoney(n: number): string
	local s   = tostring(math.floor(n))
	local len = #s
	local out = ""
	for i = 1, len do
		if i > 1 and (len - i + 1) % 3 == 0 then
			out = out .. ","
		end
		out = out .. string.sub(s, i, i)
	end
	return out
end

-- ======================================================================
-- 사운드 헬퍼
-- ======================================================================

-- 로컬 사운드 재생: SoundService 아래 Sound 인스턴스를 생성해 재생하고 Debris 로 자동 정리
local function playSound(soundId: string, volume: number?)
	local vol = volume or (GameConfig.Sounds and GameConfig.Sounds.volume or 0.55)
	pcall(function()
		local snd = Instance.new("Sound")
		snd.SoundId = soundId
		snd.Volume  = vol
		snd.Parent  = SoundService
		snd:Play()
		Debris:AddItem(snd, 6) -- 6초 후 자동 제거
	end)
end

-- ======================================================================
-- 상점 카드용 알파카 3D 미리보기 (ViewportFrame)
-- ======================================================================
-- 서버가 ReplicatedStorage.AlpacaPreviews 에 만들어 둔 종별 모델을 Clone 하여
-- 카드 안에 실제 알파카 외형을 보여줍니다(이미지 에셋 없이 모델 그대로 렌더).
local _previewFolder: Instance? = nil
local _previewSearched = false
local function getPreviewFolder(): Instance?
	if _previewFolder then return _previewFolder end
	if _previewSearched then return nil end -- 이미 한 번 기다려봤으면 더 안 막음(카드마다 5초씩 멈추는 것 방지)
	_previewSearched = true
	_previewFolder = ReplicatedStorage:FindFirstChild("AlpacaPreviews")
		or ReplicatedStorage:WaitForChild("AlpacaPreviews", 8)
	return _previewFolder
end

local function setupPreview(vf: ViewportFrame, def: any)
	local folder = getPreviewFolder()
	local template = folder and folder:FindFirstChild(def.id)
	if not template then
		vf.BackgroundColor3 = def.bodyColor -- 미리보기 없으면 종 색으로 대체
		return
	end
	local model = (template :: Model):Clone()
	model.Parent = vf

	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	vf.CurrentCamera = cam
	cam.Parent = vf

	-- 부드러운 조명
	vf.Ambient        = Color3.fromRGB(196, 194, 190)
	vf.LightColor     = Color3.fromRGB(255, 252, 245)
	vf.LightDirection = Vector3.new(-0.4, -1, -0.6)

	-- 모델 전체가 들어오도록 카메라 프레이밍 (얼굴 쪽에서 3/4 앵글)
	local cf, size = model:GetBoundingBox()
	local center   = cf.Position
	local extent   = math.max(size.X, size.Y, size.Z)
	local dist     = (extent / math.tan(math.rad(cam.FieldOfView * 0.5))) * 0.62
	local dir      = Vector3.new(0.55, 0.32, -1).Unit -- 얼굴(-Z) 쪽에서 비스듬히 내려다봄
	cam.CFrame     = CFrame.lookAt(center + dir * dist, center)
end

-- ======================================================================
-- 루트 ScreenGui
-- ======================================================================
local gui = make("ScreenGui", {
	Name           = "AlpacaFarmUI",
	ResetOnSpawn   = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
}, playerGui) :: ScreenGui

-- ======================================================================
-- 토스트 알림 시스템 (화면 상단 중앙)
-- ======================================================================
local toastHolder = makeFrame({
	Size                   = UDim2.new(0, 420, 0, 0),
	Position               = UDim2.new(0.5, -210, 0, 60),
	BackgroundTransparency = 1,
	AutomaticSize          = Enum.AutomaticSize.Y,
	ZIndex                 = 60,
}, gui)
make("UIListLayout", {
	Padding             = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment   = Enum.VerticalAlignment.Top,
	SortOrder           = Enum.SortOrder.LayoutOrder,
}, toastHolder)

local toastOrder = 0

local function showToast(message: string, isError: boolean?)
	toastOrder += 1
	local bgColor = (isError == true)
		and Color3.fromRGB(178, 58, 58)
		or  Color3.fromRGB(62, 46, 30)
	local toast = makeLabel(message, {
		Size                   = UDim2.new(1, 0, 0, 46),
		BackgroundColor3       = bgColor,
		BackgroundTransparency = 0.06,
		TextColor3             = Color3.fromRGB(255, 248, 228),
		LayoutOrder            = toastOrder,
		ZIndex                 = 60,
	}, toastHolder)
	corner(11, toast)
	make("UIPadding", {
		PaddingLeft   = UDim.new(0, 16),
		PaddingRight  = UDim.new(0, 16),
		PaddingTop    = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, toast)

	-- 2.5초 후 페이드아웃 → 제거
	task.delay(2.5, function()
		if not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.4), {
			BackgroundTransparency = 1,
			TextTransparency       = 1,
		}):Play()
		task.delay(0.45, function()
			if toast.Parent then toast:Destroy() end
		end)
	end)
end

-- ======================================================================
-- 상단 HUD — 좌상단 정보 바
-- ======================================================================
local hudLeft = makeFrame({
	Size                   = UDim2.new(0, 318, 0, 78),
	Position               = UDim2.new(0, 12, 0, 12),
	BackgroundColor3       = Color3.fromRGB(255, 248, 230),
	BackgroundTransparency = 0.06,
}, gui)
corner(14, hudLeft)
make("UIStroke", { Color = Color3.fromRGB(208, 178, 125), Thickness = 1.5 }, hudLeft)
make("UIPadding", {
	PaddingLeft   = UDim.new(0, 12),
	PaddingRight  = UDim.new(0, 12),
	PaddingTop    = UDim.new(0, 7),
	PaddingBottom = UDim.new(0, 7),
}, hudLeft)
make("UIListLayout", {
	Padding       = UDim.new(0, 2),
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder     = Enum.SortOrder.LayoutOrder,
}, hudLeft)

local moneyLabel = makeLabel("💰 0", {
	Size           = UDim2.new(1, 0, 0, 28),
	TextColor3     = Color3.fromRGB(125, 82, 12),
	Font           = Enum.Font.FredokaOne,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder    = 1,
}, hudLeft)

local slotLabel = makeLabel("보유 0 / 최대 0", {
	Size           = UDim2.new(1, 0, 0, 20),
	TextColor3     = Color3.fromRGB(96, 68, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder    = 2,
}, hudLeft)

local dexLabel = makeLabel(("📖 도감 0/%d"):format(GameConfig.DexTotal), {
	Size           = UDim2.new(1, 0, 0, 20),
	TextColor3     = Color3.fromRGB(96, 68, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder    = 3,
}, hudLeft)

-- ======================================================================
-- 상단 HUD — 우상단 버튼 4개
-- ======================================================================
local hudRight = makeFrame({
	Size                   = UDim2.new(0, 218, 0, 50),
	Position               = UDim2.new(1, -228, 0, 12),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	Padding             = UDim.new(0, 6),
	FillDirection       = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment   = Enum.VerticalAlignment.Center,
	SortOrder           = Enum.SortOrder.LayoutOrder,
}, hudRight)

local function topIconBtn(emoji: string, color: Color3, order: number): TextButton
	local btn = makeButton(emoji, color, {
		Size        = UDim2.new(0, 48, 0, 48),
		LayoutOrder = order,
		ZIndex      = 5,
	}, hudRight)
	corner(13, btn)
	return btn
end

local shopBtn = topIconBtn("🛒", Color3.fromRGB(85, 168, 85),  1)
local dexBtn  = topIconBtn("📖", Color3.fromRGB(85, 132, 200), 2)
local rankBtn = topIconBtn("🏆", Color3.fromRGB(192, 152, 45), 3)
local woolBtn = topIconBtn("🧺", Color3.fromRGB(162, 108, 190), 4)

-- ======================================================================
-- 빠른이동 버튼 (우측, 기존 4개 아이콘 버튼 아래 세로 스택)
-- hudRight 의 하단 = y 12 + 50 = 62. 여기서 8px 아래인 y=70 에 배치
-- ======================================================================
local teleportStack = makeFrame({
	Size                   = UDim2.new(0, 140, 0, 0),
	Position               = UDim2.new(1, -150, 0, 70), -- 우측 10px 여백
	BackgroundTransparency = 1,
	AutomaticSize          = Enum.AutomaticSize.Y,
	ZIndex                 = 5,
}, gui)
make("UIListLayout", {
	Padding             = UDim.new(0, 6),
	FillDirection       = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment   = Enum.VerticalAlignment.Top,
	SortOrder           = Enum.SortOrder.LayoutOrder,
}, teleportStack)

-- 가게로 버튼
local shopTpBtn = makeButton("🏪 가게로", Color3.fromRGB(78, 152, 212), {
	Size        = UDim2.new(1, 0, 0, 54),
	LayoutOrder = 1,
	ZIndex      = 5,
}, teleportStack)
corner(13, shopTpBtn)

-- 내 농장 버튼
local homeTpBtn = makeButton("🏠 내 농장", Color3.fromRGB(85, 168, 85), {
	Size        = UDim2.new(1, 0, 0, 54),
	LayoutOrder = 2,
	ZIndex      = 5,
}, teleportStack)
corner(13, homeTpBtn)

-- 빠른이동 버튼 핸들러는 closeAllPanels() 정의 이후(아래)에서 연결한다.
-- (이동 시 열려있던 상점 등 팝업을 함께 닫기 위함)

-- ======================================================================
-- 패널 공통 유틸
-- ======================================================================

-- 패널 참조 (do 블록 안에서 할당, 클로저에서 활용)
local shopFrame: any = nil
local dexFrame:  any = nil
local rankFrame: any = nil

-- 열린 패널을 모두 닫음
local function closeAllPanels()
	if shopFrame then shopFrame.Visible = false end
	if dexFrame  then dexFrame.Visible  = false end
	if rankFrame then rankFrame.Visible = false end
end

-- ======================================================================
-- 빠른이동 버튼 핸들러 (click → teleport 효과음 → 서버 요청)
-- 이동 시 열려있던 팝업(상점/도감/순위)을 자동으로 닫는다.
-- ======================================================================
shopTpBtn.Activated:Connect(function()
	playSound(GameConfig.Sounds.click)
	playSound(GameConfig.Sounds.teleport)
	closeAllPanels()
	Remotes.Event("RequestTeleport"):FireServer("shop")
end)

homeTpBtn.Activated:Connect(function()
	playSound(GameConfig.Sounds.click)
	playSound(GameConfig.Sounds.teleport)
	closeAllPanels() -- 내 농장으로 돌아가면 상점 등 팝업을 닫음
	Remotes.Event("RequestTeleport"):FireServer("home")
end)

-- ======================================================================
-- 상점 구역을 벗어나면 상점 팝업을 자동으로 닫는다.
-- (가게 패드에서 일정 거리 이상 멀어지면 닫힘 → 걸어서 가게를 벗어나는 경우 커버)
-- ======================================================================
do
	local shopPad: BasePart? = nil
	task.spawn(function()
		local farm = workspace:WaitForChild("AlpacaFarm", 30)
		local shop = farm and farm:WaitForChild("Shop", 15)
		shopPad = shop and (shop:WaitForChild("ShopPad", 15) :: any)
	end)
	local CLOSE_DISTANCE = 40 -- 패드 기준 수평 거리(studs)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.25 then return end -- 0.25초마다만 검사(가벼움)
		acc = 0
		if not shopFrame or not shopFrame.Visible then return end
		if not shopPad then return end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local d = (root :: BasePart).Position - shopPad.Position
		if Vector3.new(d.X, 0, d.Z).Magnitude > CLOSE_DISTANCE then
			shopFrame.Visible = false
		end
	end)
end

-- 패널 베이스 생성: 560×520 중앙 패널 + 헤더 + ✕ 버튼
local function makePanelBase(title: string): (Frame, TextButton)
	local panel = makeFrame({
		Size             = UDim2.new(0, 580, 0, 530),
		Position         = UDim2.new(0.5, -290, 0.5, -265),
		BackgroundColor3 = Color3.fromRGB(255, 250, 238),
		Visible          = false,
		ZIndex           = 20,
	}, gui)
	corner(18, panel)
	make("UIStroke", { Color = Color3.fromRGB(202, 172, 118), Thickness = 2 }, panel)

	-- 헤더 바
	local header = makeFrame({
		Size             = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Color3.fromRGB(238, 215, 165),
		ZIndex           = 21,
	}, panel)
	corner(18, header)
	makeLabel(title, {
		Size           = UDim2.new(1, -62, 1, 0),
		Position       = UDim2.new(0, 16, 0, 0),
		TextColor3     = Color3.fromRGB(72, 46, 12),
		Font           = Enum.Font.FredokaOne,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex         = 22,
	}, header)

	local closeBtn = makeButton("✕", Color3.fromRGB(198, 82, 72), {
		Size     = UDim2.new(0, 36, 0, 36),
		Position = UDim2.new(1, -44, 0, 10),
		ZIndex   = 22,
	}, panel)
	corner(8, closeBtn)
	closeBtn.Activated:Connect(function()
		panel.Visible = false
	end)

	return panel, closeBtn
end

-- ======================================================================
-- 상점 패널
-- ======================================================================
local updateShopSlotBtn: any = nil  -- PlayerDataUpdated 에서 호출하기 위한 참조

do
	local panel = makePanelBase("🛒 알파카 상점")
	shopFrame = panel

	-- 알파카 카드 스크롤 (패널 높이 - 헤더 - 하단 고정 영역)
	local scroll = make("ScrollingFrame", {
		Size                = UDim2.new(1, -24, 1, -176),
		Position            = UDim2.new(0, 12, 0, 64),
		BackgroundTransparency = 1,
		CanvasSize          = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness  = 6,
		ZIndex              = 20,
	}, panel)
	make("UIGridLayout", {
		CellSize    = UDim2.new(0, 168, 0, 196),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder   = Enum.SortOrder.LayoutOrder,
	}, scroll)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingTop  = UDim.new(0, 6),
	}, scroll)

	-- 등급 순 정렬 후 카드 생성
	local sorted = table.clone(GameConfig.Alpacas)
	table.sort(sorted, function(a, b)
		local ao = (GameConfig.Rarities[a.rarity] and GameConfig.Rarities[a.rarity].order) or 99
		local bo = (GameConfig.Rarities[b.rarity] and GameConfig.Rarities[b.rarity].order) or 99
		if ao ~= bo then return ao < bo end
		return (a.price or 0) < (b.price or 0)
	end)

	for idx, def in ipairs(sorted) do
		local rInfo   = GameConfig.Rarities[def.rarity]
			or { displayName = def.rarity, color = Color3.fromRGB(180, 180, 180), order = 99 }
		local isRobux = def.currency == "Robux"

		local card = makeFrame({
			BackgroundColor3 = Color3.fromRGB(255, 252, 244),
			LayoutOrder      = idx,
			ZIndex           = 20,
		}, scroll)
		corner(12, card)
		make("UIStroke", { Color = rInfo.color, Thickness = 2.5 }, card)

		-- 알파카 3D 미리보기 (실제 모델을 ViewportFrame 으로 렌더 → 고르기 도움)
		local preview = make("ViewportFrame", {
			Size             = UDim2.new(1, -12, 0, 64),
			Position         = UDim2.new(0, 6, 0, 6),
			BackgroundColor3 = Color3.fromRGB(247, 243, 234),
			ZIndex           = 21,
		}, card) :: ViewportFrame
		corner(8, preview)
		setupPreview(preview, def)

		makeLabel(def.displayName, {
			Size           = UDim2.new(1, -8, 0, 24),
			Position       = UDim2.new(0, 4, 0, 74),
			TextColor3     = Color3.fromRGB(52, 36, 12),
			Font           = Enum.Font.FredokaOne,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex         = 21,
		}, card)

		makeLabel("[" .. rInfo.displayName .. "]", {
			Size           = UDim2.new(1, -8, 0, 18),
			Position       = UDim2.new(0, 4, 0, 100),
			TextColor3     = rInfo.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex         = 21,
		}, card)

		makeLabel(("케어 +%d  양털 $%d"):format(def.careReward, def.woolValue), {
			Size           = UDim2.new(1, -8, 0, 18),
			Position       = UDim2.new(0, 4, 0, 120),
			TextColor3     = Color3.fromRGB(98, 76, 40),
			Font           = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex         = 21,
		}, card)

		-- 구매 / 안내 버튼
		local btnText  = isRobux and "🔒 출시 예정" or ("💰 " .. formatMoney(def.price))
		local btnColor = isRobux
			and Color3.fromRGB(128, 118, 100)
			or  Color3.fromRGB(86, 165, 84)
		local buyBtn = makeButton(btnText, btnColor, {
			Size     = UDim2.new(1, -12, 0, 32),
			Position = UDim2.new(0, 6, 1, -38),
			ZIndex   = 21,
		}, card)
		corner(8, buyBtn)

		buyBtn.Activated:Connect(function()
			playSound(GameConfig.Sounds.click) -- 구매 버튼 클릭 효과음
			if isRobux then
				showToast("해당 알파카는 출시 후 제공됩니다 🦙")
			else
				Remotes.Event("RequestBuyAlpaca"):FireServer(def.id)
			end
		end)
	end

	-- 하단 고정 영역: 슬롯 확장 + 황금 갈퀴 게임패스
	local bottom = makeFrame({
		Size             = UDim2.new(1, -24, 0, 100),
		Position         = UDim2.new(0, 12, 1, -108),
		BackgroundColor3 = Color3.fromRGB(241, 230, 202),
		ZIndex           = 20,
	}, panel)
	corner(12, bottom)
	make("UIStroke", { Color = Color3.fromRGB(192, 162, 108), Thickness = 1 }, bottom)
	make("UIPadding", {
		PaddingLeft   = UDim.new(0, 10),
		PaddingRight  = UDim.new(0, 10),
		PaddingTop    = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, bottom)
	make("UIListLayout", {
		Padding           = UDim.new(0, 8),
		FillDirection     = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder         = Enum.SortOrder.LayoutOrder,
	}, bottom)

	-- 슬롯 확장 버튼
	local expandBtn = makeButton("🏠 슬롯 확장\n...", Color3.fromRGB(78, 152, 212), {
		Size        = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 1,
		ZIndex      = 21,
	}, bottom)
	corner(10, expandBtn)

	-- 황금 갈퀴 게임패스 버튼
	local boost    = GameConfig.Monetization.incomeBoost
	local passBtn  = makeButton(
		("✨ %s\n%dR$"):format(boost.displayName, boost.robuxPrice),
		Color3.fromRGB(190, 148, 34),
		{ Size = UDim2.new(0.5, -4, 1, 0), LayoutOrder = 2, ZIndex = 21 },
		bottom
	)
	corner(10, passBtn)

	-- 슬롯 버튼 텍스트 갱신
	local function refreshExpandBtn()
		if not data then return end
		local cost = GameConfig.getNextSlotCost(data.slots or 0)
		if cost then
			expandBtn.Text             = ("🏠 슬롯 확장\n💰 %s"):format(formatMoney(cost))
			expandBtn.BackgroundColor3 = Color3.fromRGB(78, 152, 212)
		else
			expandBtn.Text             = "🏠 슬롯\n최대"
			expandBtn.BackgroundColor3 = Color3.fromRGB(138, 136, 128)
		end
	end
	-- 외부(PlayerDataUpdated 핸들러)에서 호출할 수 있도록 저장
	updateShopSlotBtn = refreshExpandBtn

	expandBtn.Activated:Connect(function()
		playSound(GameConfig.Sounds.click) -- 슬롯 확장 버튼 클릭 효과음
		if not data then return end
		local cost = GameConfig.getNextSlotCost(data.slots or 0)
		if cost then
			Remotes.Event("RequestExpandSlot"):FireServer()
		else
			showToast("슬롯이 이미 최대입니다!")
		end
	end)

	passBtn.Activated:Connect(function()
		Remotes.Event("RequestBuyGamePass"):FireServer("incomeBoost")
	end)

	-- 상점 토글 버튼
	shopBtn.Activated:Connect(function()
		local wasOpen = shopFrame.Visible
		closeAllPanels()
		if not wasOpen then
			shopFrame.Visible = true
			refreshExpandBtn()
		end
	end)

	-- 서버(농장 패드 등)가 상점 열기를 요청할 때
	Remotes.Event("OpenShopRequest").OnClientEvent:Connect(function()
		closeAllPanels()
		shopFrame.Visible = true
		refreshExpandBtn()
	end)
end -- 상점 블록 끝

-- ======================================================================
-- 도감 패널
-- ======================================================================

-- defId → 카드 갱신 클로저 (owned: boolean)
local dexUpdateFuncs: { [string]: (boolean) -> () } = {}

do
	local panel = makePanelBase("📖 알파카 도감")
	dexFrame = panel

	local scroll = make("ScrollingFrame", {
		Size                = UDim2.new(1, -24, 1, -72),
		Position            = UDim2.new(0, 12, 0, 64),
		BackgroundTransparency = 1,
		CanvasSize          = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness  = 6,
		ZIndex              = 20,
	}, panel)
	make("UIGridLayout", {
		CellSize    = UDim2.new(0, 108, 0, 122),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder   = Enum.SortOrder.LayoutOrder,
	}, scroll)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingTop  = UDim.new(0, 6),
	}, scroll)

	-- countInDex 종만 등급 순 정렬
	local dexAlpacas: { any } = {}
	for _, def in ipairs(GameConfig.Alpacas) do
		if def.countInDex then
			table.insert(dexAlpacas, def)
		end
	end
	table.sort(dexAlpacas, function(a, b)
		local ao = (GameConfig.Rarities[a.rarity] and GameConfig.Rarities[a.rarity].order) or 99
		local bo = (GameConfig.Rarities[b.rarity] and GameConfig.Rarities[b.rarity].order) or 99
		return ao < bo
	end)

	for idx, def in ipairs(dexAlpacas) do
		local rInfo = GameConfig.Rarities[def.rarity]
			or { displayName = def.rarity, color = Color3.fromRGB(180, 180, 180), order = 99 }
		local defId = def.id :: string

		-- 카드 (미보유 기본 색)
		local card = makeFrame({
			BackgroundColor3 = Color3.fromRGB(192, 182, 162),
			LayoutOrder      = idx,
			ZIndex           = 20,
		}, scroll)
		corner(10, card)

		-- 색상 미리보기 (미보유: 어둡게)
		local colorBox = makeFrame({
			Size             = UDim2.new(1, -10, 0, 62),
			Position         = UDim2.new(0, 5, 0, 5),
			BackgroundColor3 = Color3.fromRGB(126, 120, 110),
			ZIndex           = 21,
		}, card)
		corner(6, colorBox)

		local nameLabel = makeLabel("???", {
			Size           = UDim2.new(1, -8, 0, 22),
			Position       = UDim2.new(0, 4, 0, 70),
			TextColor3     = Color3.fromRGB(114, 104, 92),
			Font           = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex         = 21,
		}, card)

		local rarLabel = makeLabel("[" .. rInfo.displayName .. "]", {
			Size           = UDim2.new(1, -8, 0, 16),
			Position       = UDim2.new(0, 4, 0, 94),
			TextColor3     = Color3.fromRGB(144, 135, 122),
			Font           = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex         = 21,
		}, card)

		-- 갱신 클로저 등록 (PlayerDataUpdated 수신 시 호출됨)
		dexUpdateFuncs[defId] = function(owned: boolean)
			if owned then
				-- 보유: 원래 색 + 등급 테두리
				card.BackgroundColor3    = Color3.fromRGB(255, 252, 244)
				colorBox.BackgroundColor3 = def.bodyColor
				nameLabel.Text           = def.displayName
				nameLabel.TextColor3     = Color3.fromRGB(52, 36, 12)
				rarLabel.TextColor3      = rInfo.color
				local stroke = card:FindFirstChildOfClass("UIStroke")
				if not stroke then
					make("UIStroke", { Color = rInfo.color, Thickness = 2 }, card)
				end
			else
				-- 미보유: 어둡게 + "???"
				card.BackgroundColor3    = Color3.fromRGB(192, 182, 162)
				colorBox.BackgroundColor3 = Color3.fromRGB(126, 120, 110)
				nameLabel.Text           = "???"
				nameLabel.TextColor3     = Color3.fromRGB(114, 104, 92)
				rarLabel.TextColor3      = Color3.fromRGB(144, 135, 122)
				local stroke = card:FindFirstChildOfClass("UIStroke")
				if stroke then stroke:Destroy() end
			end
		end
	end

	dexBtn.Activated:Connect(function()
		local wasOpen = dexFrame.Visible
		closeAllPanels()
		if not wasOpen then
			dexFrame.Visible = true
		end
	end)
end -- 도감 블록 끝

-- ======================================================================
-- 순위 패널
-- ======================================================================
do
	local panel = makePanelBase("🏆 알파카 부자 순위")
	rankFrame = panel

	-- 내 총자산 표시 바
	local myWorthLabel = makeLabel("내 총자산: 💰 0", {
		Size                   = UDim2.new(1, -24, 0, 40),
		Position               = UDim2.new(0, 12, 0, 64),
		BackgroundColor3       = Color3.fromRGB(238, 212, 155),
		BackgroundTransparency = 0,
		TextColor3             = Color3.fromRGB(98, 66, 16),
		Font                   = Enum.Font.GothamBold,
		TextXAlignment         = Enum.TextXAlignment.Left,
		ZIndex                 = 21,
	}, panel)
	corner(10, myWorthLabel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, myWorthLabel)

	local lbScroll = make("ScrollingFrame", {
		Size                = UDim2.new(1, -24, 1, -122),
		Position            = UDim2.new(0, 12, 0, 112),
		BackgroundTransparency = 1,
		CanvasSize          = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness  = 6,
		ZIndex              = 20,
	}, panel)
	make("UIListLayout", {
		Padding   = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, lbScroll)

	-- 캐시 (패널이 닫혀있을 때 LeaderboardUpdated 보관)
	local cachedEntries: { any } = {}
	local cachedMyWorth = 0

	local function renderLb(entries: { any }, myWorth: number)
		cachedEntries = entries
		cachedMyWorth = myWorth
		myWorthLabel.Text = ("내 총자산: 💰 %s"):format(formatMoney(myWorth))

		-- 기존 행 정리
		for _, c in ipairs(lbScroll:GetChildren()) do
			if c:IsA("Frame") or c:IsA("TextLabel") then
				c:Destroy()
			end
		end

		if #entries == 0 then
			makeLabel("아직 순위 데이터가 없어요 🦙", {
				Size       = UDim2.new(1, 0, 0, 44),
				TextColor3 = Color3.fromRGB(152, 134, 104),
				ZIndex     = 21,
			}, lbScroll)
			return
		end

		for _, e in ipairs(entries) do
			local r     = e.rank :: number
			local medal = r == 1 and "🥇"
				or (r == 2 and "🥈"
				or (r == 3 and "🥉"
				or (tostring(r) .. ".")))
			local rowBg = r <= 3
				and Color3.fromRGB(255, 246, 196)
				or  Color3.fromRGB(248, 242, 228)
			local row = makeFrame({
				Size             = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = rowBg,
				LayoutOrder      = r,
				ZIndex           = 21,
			}, lbScroll)
			corner(8, row)
			makeLabel(
				("%s  %s    💰 %s"):format(medal, tostring(e.name), formatMoney(e.worth or 0)),
				{
					Size           = UDim2.fromScale(1, 1),
					TextColor3     = r <= 3 and Color3.fromRGB(130, 84, 6) or Color3.fromRGB(72, 54, 24),
					Font           = r <= 3 and Enum.Font.GothamBold or Enum.Font.GothamMedium,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex         = 22,
				},
				row
			)
			make("UIPadding", { PaddingLeft = UDim.new(0, 14) }, row)
		end
	end

	-- 순위 패널 열기: 서버에서 최신 데이터 요청
	local function openRank()
		closeAllPanels()
		rankFrame.Visible = true
		task.spawn(function()
			local ok, result = pcall(function()
				return Remotes.Function("GetLeaderboard"):InvokeServer()
			end)
			if ok and result then
				renderLb(result.entries or {}, result.myWorth or 0)
			else
				renderLb(cachedEntries, cachedMyWorth)
			end
		end)
	end

	rankBtn.Activated:Connect(function()
		if rankFrame.Visible then
			rankFrame.Visible = false
		else
			openRank()
		end
	end)

	-- 서버 브로드캐스트 수신: 패널이 열려있으면 즉시 갱신
	Remotes.Event("LeaderboardUpdated").OnClientEvent:Connect(function(entries: any)
		if rankFrame.Visible then
			renderLb(entries or {}, cachedMyWorth)
		else
			cachedEntries = entries or {}
		end
	end)
end -- 순위 블록 끝

-- ======================================================================
-- HUD / 도감 갱신 함수
-- ======================================================================

local function refreshHud()
	if not data then return end
	local alpacaCount = #(data.alpacas or {})
	local slots       = data.slots or 0
	local dexCount    = 0
	for _ in pairs(data.dex or {}) do
		dexCount += 1
	end
	moneyLabel.Text = "💰 " .. formatMoney(data.money or 0)
	slotLabel.Text  = ("보유 %d / 최대 %d"):format(alpacaCount, slots)
	dexLabel.Text   = ("📖 도감 %d/%d"):format(dexCount, GameConfig.DexTotal)
end

local function refreshDex()
	if not data then return end
	local dex = data.dex or {}
	for defId, fn in pairs(dexUpdateFuncs) do
		fn(dex[defId] == true)
	end
end

-- ======================================================================
-- 이벤트 연결
-- ======================================================================

-- 양털 전체 수집 버튼
woolBtn.Activated:Connect(function()
	playSound(GameConfig.Sounds.click) -- 양털 수집 버튼 클릭 효과음
	Remotes.Event("RequestCollectWool"):FireServer(nil)
end)

-- 서버 알림 토스트
Remotes.Event("Notify").OnClientEvent:Connect(function(message: string, isError: boolean?)
	showToast(message, isError)
	if isError == true then
		-- 오류 알림: error 효과음
		playSound(GameConfig.Sounds.error)
	elseif string.find(message, "입양 완료", 1, true) then
		-- 알파카 구매 성공 알림: buy 효과음
		playSound(GameConfig.Sounds.buy)
	end
end)

-- 양털 수집 결과 토스트
Remotes.Event("WoolCollected").OnClientEvent:Connect(function(amount: number)
	if amount > 0 then
		showToast("🧺 양털 판매 +💰" .. formatMoney(amount))
		playSound(GameConfig.Sounds.wool) -- 양털 수집 성공 효과음
	else
		showToast("적립된 양털이 없어요 🦙")
		playSound(GameConfig.Sounds.error) -- 양털 없음: error 효과음
	end
end)

-- 플레이어 데이터 갱신: HUD + 도감 + 상점 슬롯 버튼
Remotes.Event("PlayerDataUpdated").OnClientEvent:Connect(function(newData: any)
	data = newData
	refreshHud()
	refreshDex()
	-- 상점이 열려있으면 슬롯 확장 버튼 텍스트도 갱신
	if shopFrame and shopFrame.Visible and updateShopSlotBtn then
		updateShopSlotBtn()
	end
end)

-- ======================================================================
-- 초기 데이터 요청 (서버 로드 완료 후 한 번)
-- ======================================================================
task.spawn(function()
	local ok, result = pcall(function()
		return Remotes.Function("GetPlayerData"):InvokeServer()
	end)
	if ok and result then
		data = result
		refreshHud()
		refreshDex()
	end
end)

-- ======================================================================
-- 알파카 이름짓기 모달 (구매 직후 서버가 PromptNameAlpaca 로 호출)
-- ======================================================================
local nameDialog: Frame? = nil
local function showNameDialog(uid: string, defId: string, speciesName: string)
	if nameDialog then
		nameDialog:Destroy()
		nameDialog = nil
	end
	local def = (GameConfig.AlpacasById :: any)[defId]

	local overlay = makeFrame({
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex                 = 80,
		Active                 = true, -- 뒤의 상점 버튼 클릭 차단(진짜 모달) → 이름짓는 중 또 구매해 첫 모달이 사라지는 것 방지
	}, gui)
	nameDialog = overlay

	local box = makeFrame({
		Size             = UDim2.new(0, 360, 0, 232),
		Position         = UDim2.new(0.5, -180, 0.5, -116),
		BackgroundColor3 = Color3.fromRGB(255, 252, 244),
		ZIndex           = 81,
	}, overlay)
	corner(16, box)
	make("UIStroke", { Color = (def and def.accentColor) or Color3.fromRGB(120, 120, 120), Thickness = 3 }, box)

	makeLabel("🦙 새 가족 이름 짓기", {
		Size       = UDim2.new(1, -24, 0, 34),
		Position   = UDim2.new(0, 12, 0, 14),
		Font       = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(52, 36, 12),
		ZIndex     = 82,
	}, box)

	makeLabel(speciesName .. " 에게 이름을 지어주세요!", {
		Size       = UDim2.new(1, -24, 0, 22),
		Position   = UDim2.new(0, 12, 0, 52),
		TextColor3 = Color3.fromRGB(120, 96, 56),
		ZIndex     = 82,
	}, box)

	local input = make("TextBox", {
		Size             = UDim2.new(1, -32, 0, 48),
		Position         = UDim2.new(0, 16, 0, 86),
		BackgroundColor3 = Color3.fromRGB(245, 240, 230),
		Text             = "",
		PlaceholderText  = "이름 입력 (최대 16자)",
		Font             = Enum.Font.GothamMedium,
		TextColor3       = Color3.fromRGB(40, 30, 16),
		TextScaled       = true,
		ClearTextOnFocus = false,
		MultiLine        = false,
		ZIndex           = 82,
	}, box) :: TextBox
	corner(10, input)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, input)
	make("UITextSizeConstraint", { MaxTextSize = 24 }, input)

	local function close()
		if overlay then
			overlay:Destroy()
		end
		if nameDialog == overlay then
			nameDialog = nil
		end
	end

	local function submit()
		local name = (input.Text:gsub("^%s+", ""):gsub("%s+$", ""))
		if #name > 0 then
			Remotes.Event("RequestNameAlpaca"):FireServer(uid, name)
			showToast("이름을 지었어요: " .. name .. " 🦙")
		end
		close()
	end

	local confirm = makeButton("확정 ✅", Color3.fromRGB(86, 165, 84), {
		Size     = UDim2.new(0.5, -20, 0, 44),
		Position = UDim2.new(0, 16, 1, -58),
		ZIndex   = 82,
	}, box)
	corner(10, confirm)
	confirm.Activated:Connect(submit)

	local skip = makeButton("나중에", Color3.fromRGB(150, 142, 128), {
		Size     = UDim2.new(0.5, -20, 0, 44),
		Position = UDim2.new(0.5, 4, 1, -58),
		ZIndex   = 82,
	}, box)
	corner(10, skip)
	skip.Activated:Connect(close)

	input.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
	end)
	input:CaptureFocus()
end

Remotes.Event("PromptNameAlpaca").OnClientEvent:Connect(function(uid: string, defId: string, speciesName: string)
	showNameDialog(uid, defId, speciesName)
end)

print("[UIController] 알파카 농장 UI 초기화 완료 🦙")
