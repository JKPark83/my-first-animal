--!strict
--[[
	AlpacaHud
	----------
	농장 내 모든 알파카 머리 위에 욕구/행복 게이지 BillboardGui를 실시간으로 표시합니다.

	- workspace의 AlpacaFarm 폴더를 감시하여 알파카 모델이 추가/삭제될 때
	  자동으로 HUD를 부착하거나 해제합니다.
	- 배고픔(Hunger) / 털엉킴(Tangle) / 더러움(Dirt) 3종 막대를 표시하고,
	  값이 높을수록 주황 → 빨강으로 경고색을 전환합니다.
	- 행복도(Happiness)는 하트 색으로 함께 표현됩니다.
	- MaxDistance 설정으로 너무 먼 알파카는 HUD가 가려집니다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

-- =====================================================================
-- 상수
-- =====================================================================
local HUD_STUDS_OFFSET = Vector3.new(0, 3.2, 0)  -- 루트 위로 올리는 거리
local HUD_SIZE = UDim2.new(0, 130, 0, 62)         -- BillboardGui 픽셀 크기
local MAX_DISTANCE = 60                             -- 이 거리 초과 시 HUD 숨김

-- 욕구 막대 색상 (정상 / 주의 / 위험)
local COLOR_OK      = Color3.fromRGB(100, 200, 100)   -- 초록 (낮은 욕구 = 좋음)
local COLOR_WARN    = Color3.fromRGB(240, 160, 50)    -- 주황
local COLOR_DANGER  = Color3.fromRGB(220, 60, 60)     -- 빨강

-- 행복도 하트 색상
local COLOR_HEART_HIGH = Color3.fromRGB(240, 100, 150)  -- 높은 행복
local COLOR_HEART_LOW  = Color3.fromRGB(150, 100, 100)  -- 낮은 행복

-- 욕구 임계치 (GameConfig에서 읽어 쓰기 편하게 지역 변수로)
local careThreshold   = GameConfig.Care.careThreshold     -- 20: 케어 가능 → 주의
local visualThreshold = GameConfig.Care.visualThreshold   -- Hunger:55 Tangle:50 Dirt:50 → 위험

-- =====================================================================
-- 타입
-- =====================================================================
type BarRefs = {
	hunger: Frame,
	tangle: Frame,
	dirt:   Frame,
}

type HudEntry = {
	gui:         BillboardGui,
	bars:        BarRefs,
	heartLabel:  TextLabel,
	connections: { RBXScriptConnection },
}

-- =====================================================================
-- 내부 상태 — uid → HudEntry
-- =====================================================================
local hudMap: { [string]: HudEntry } = {}

-- =====================================================================
-- 유틸 함수
-- =====================================================================

-- 욕구값에 따른 막대 색상 계산 (need 이름별 visualThreshold 다름)
local function needColor(needName: string, value: number): Color3
	local dangerLevel = (visualThreshold :: any)[needName] :: number
	if value >= dangerLevel then
		return COLOR_DANGER
	elseif value >= careThreshold then
		return COLOR_WARN
	else
		return COLOR_OK
	end
end

-- 행복도 → 하트 색상
local function heartColor(happiness: number): Color3
	local t = math.clamp(happiness / 100, 0, 1)
	return COLOR_HEART_LOW:Lerp(COLOR_HEART_HIGH, t)
end

-- =====================================================================
-- HUD 생성 함수
-- =====================================================================
local function buildHud(model: Model, defId: string): HudEntry?
	local root = model:FindFirstChild("Root") :: BasePart?
	if not root then
		-- Root가 아직 없으면 잠시 기다린 후 재시도
		root = model:WaitForChild("Root", 5) :: BasePart?
		if not root then
			return nil
		end
	end

	local def = GameConfig.AlpacasById[defId]
	local displayName = def and def.displayName or defId

	-- ── BillboardGui 생성 ──────────────────────────────────────────
	local gui = Instance.new("BillboardGui")
	gui.Name = "AlpacaHud"
	gui.Adornee = root
	gui.StudsOffset = HUD_STUDS_OFFSET
	gui.Size = HUD_SIZE
	gui.AlwaysOnTop = false
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Parent = root

	-- ── 배경 프레임 ─────────────────────────────────────────────────
	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.35
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0, 6)
	padding.PaddingRight  = UDim.new(0, 6)
	padding.PaddingTop    = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = bg

	-- ── 이름 + 하트 레이블 ──────────────────────────────────────────
	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.Size = UDim2.new(1, 0, 0, 16)
	titleRow.Position = UDim2.new(0, 0, 0, 0)
	titleRow.BackgroundTransparency = 1
	titleRow.Parent = bg

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(0.75, 0, 1, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize = 11
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = titleRow

	local heartLabel = Instance.new("TextLabel")
	heartLabel.Name = "HeartLabel"
	heartLabel.Size = UDim2.new(0.25, 0, 1, 0)
	heartLabel.Position = UDim2.new(0.75, 0, 0, 0)
	heartLabel.BackgroundTransparency = 1
	heartLabel.Text = "♥ 100"
	heartLabel.TextColor3 = COLOR_HEART_HIGH
	heartLabel.TextSize = 10
	heartLabel.Font = Enum.Font.GothamBold
	heartLabel.TextXAlignment = Enum.TextXAlignment.Right
	heartLabel.Parent = titleRow

	-- ── 욕구 막대 3개 ────────────────────────────────────────────────
	-- 레이아웃: 이름행(16px) + 간격(2px) + 막대3개(각12px+2px간격)
	local barDefs = {
		{ needName = "Hunger", label = "🍃 배고픔", yPos = 20 },
		{ needName = "Tangle", label = "🪮 엉킴",   yPos = 34 },
		{ needName = "Dirt",   label = "🛁 더러움", yPos = 48 },
	}

	local bars: BarRefs = {} :: BarRefs

	for _, bd in ipairs(barDefs) do
		-- 줄 컨테이너
		local row = Instance.new("Frame")
		row.Name = bd.needName .. "Row"
		row.Size = UDim2.new(1, 0, 0, 10)
		row.Position = UDim2.new(0, 0, 0, bd.yPos)
		row.BackgroundTransparency = 1
		row.Parent = bg

		-- 레이블
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.new(0.34, 0, 1, 0)
		lbl.Position = UDim2.new(0, 0, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = bd.label
		lbl.TextColor3 = Color3.fromRGB(210, 210, 210)
		lbl.TextSize = 9
		lbl.Font = Enum.Font.Gotham
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		-- 막대 배경 (회색 트랙)
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Size = UDim2.new(0.64, 0, 1, 0)
		track.Position = UDim2.new(0.36, 0, 0, 0)
		track.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		track.BorderSizePixel = 0
		track.Parent = row

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		-- 막대 채움
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(0, 0, 1, 0)   -- 초기 너비 0 → 갱신 함수에서 설정
		fill.Position = UDim2.new(0, 0, 0, 0)
		fill.BackgroundColor3 = COLOR_OK
		fill.BorderSizePixel = 0
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		-- bars 테이블에 fill 참조 저장
		if bd.needName == "Hunger" then
			bars.hunger = fill
		elseif bd.needName == "Tangle" then
			bars.tangle = fill
		else
			bars.dirt = fill
		end
	end

	return {
		gui        = gui,
		bars       = bars,
		heartLabel = heartLabel,
		connections = {},
	}
end

-- =====================================================================
-- 게이지 갱신 함수
-- =====================================================================
local function updateHud(entry: HudEntry, model: Model)
	local hunger    = (model:GetAttribute("Hunger")    :: number?) or 0
	local tangle    = (model:GetAttribute("Tangle")    :: number?) or 0
	local dirt      = (model:GetAttribute("Dirt")      :: number?) or 0
	local happiness = (model:GetAttribute("Happiness") :: number?) or 100

	-- 막대 채움 비율: 욕구값이 높을수록 막대가 꽉 참
	local hungerRatio = math.clamp(hunger / 100, 0, 1)
	local tangleRatio = math.clamp(tangle / 100, 0, 1)
	local dirtRatio   = math.clamp(dirt   / 100, 0, 1)

	entry.bars.hunger.Size           = UDim2.new(hungerRatio, 0, 1, 0)
	entry.bars.hunger.BackgroundColor3 = needColor("Hunger", hunger)

	entry.bars.tangle.Size           = UDim2.new(tangleRatio, 0, 1, 0)
	entry.bars.tangle.BackgroundColor3 = needColor("Tangle", tangle)

	entry.bars.dirt.Size             = UDim2.new(dirtRatio, 0, 1, 0)
	entry.bars.dirt.BackgroundColor3 = needColor("Dirt", dirt)

	-- 하트 표시 (행복도)
	local hapInt = math.floor(happiness + 0.5)
	entry.heartLabel.Text       = "♥ " .. tostring(hapInt)
	entry.heartLabel.TextColor3 = heartColor(happiness)
end

-- =====================================================================
-- 모델 등록: HUD 생성 + 속성 변경 감지 연결
-- =====================================================================
local function registerModel(model: Model)
	local uid   = model:GetAttribute("Uid")   :: string?
	local defId = model:GetAttribute("AlpacaId") :: string?

	-- AlpacaId 또는 GetAttribute("AlpacaId") 가 없는 모델은 건너뜀
	if not defId or defId == "" then
		return
	end
	-- uid 가 없으면 defId 를 임시 키로 사용(스폰 직후 uid 설정 전 방어)
	local key = uid or defId

	-- 이미 등록된 경우 중복 방지
	if hudMap[key] then
		return
	end

	local entry = buildHud(model, defId)
	if not entry then
		return
	end

	-- 초기 값으로 한 번 갱신
	updateHud(entry, model)

	-- 속성 변경 감지 (실시간 갱신)
	local needNames = { "Hunger", "Tangle", "Dirt", "Happiness" }
	for _, attr in ipairs(needNames) do
		local conn = model:GetAttributeChangedSignal(attr):Connect(function()
			if hudMap[key] then
				updateHud(hudMap[key], model)
			end
		end)
		table.insert(entry.connections, conn)
	end

	-- uid 가 나중에 설정될 경우를 대비해 AlpacaId 변경도 감시
	local uidConn = model:GetAttributeChangedSignal("Uid"):Connect(function()
		local newUid = model:GetAttribute("Uid") :: string?
		if newUid and newUid ~= "" and newUid ~= key then
			-- 키가 바뀌면 기존 항목을 새 uid 로 이동
			local existing = hudMap[key]
			if existing then
				hudMap[key] = nil
				hudMap[newUid] = existing
			end
		end
	end)
	table.insert(entry.connections, uidConn)

	hudMap[key] = entry
end

-- =====================================================================
-- 모델 등록 해제: 연결 끊기 + GUI 제거
-- =====================================================================
local function unregisterModel(model: Model)
	local uid   = model:GetAttribute("Uid")    :: string?
	local defId = model:GetAttribute("AlpacaId") :: string?
	local key   = uid or defId

	if not key then
		return
	end

	local entry = hudMap[key]
	if entry then
		-- 모든 이벤트 연결 해제
		for _, conn in ipairs(entry.connections) do
			conn:Disconnect()
		end
		-- GUI 제거 (model이 이미 제거됐으면 gui도 사라지지만 안전하게 처리)
		if entry.gui and entry.gui.Parent then
			entry.gui:Destroy()
		end
		hudMap[key] = nil
	end
end

-- =====================================================================
-- 자식(Descendant) 이 모델인지, 알파카 모델인지 판별
-- =====================================================================
local function isAlpacaModel(instance: Instance): boolean
	if not instance:IsA("Model") then
		return false
	end
	local alpacaId = instance:GetAttribute("AlpacaId") :: string?
	return alpacaId ~= nil and alpacaId ~= ""
end

-- =====================================================================
-- 메인 초기화
-- =====================================================================
local alpacaFarm = workspace:WaitForChild("AlpacaFarm") :: Folder

-- 이미 존재하는 알파카 모델 초기 처리
for _, descendant in ipairs(alpacaFarm:GetDescendants()) do
	if isAlpacaModel(descendant) then
		registerModel(descendant :: Model)
	end
end

-- 이후 추가되는 모델 감지
alpacaFarm.DescendantAdded:Connect(function(descendant)
	if isAlpacaModel(descendant) then
		-- 속성이 설정된 직후 스폰되는 경우를 위해 다음 프레임에서 등록
		task.defer(function()
			registerModel(descendant :: Model)
		end)
	end
end)

-- 제거되는 모델 감지
alpacaFarm.DescendantRemoving:Connect(function(descendant)
	if isAlpacaModel(descendant) then
		unregisterModel(descendant :: Model)
	end
end)
