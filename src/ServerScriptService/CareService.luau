--!strict
--[[
	CareService
	-----------
	알파카의 욕구(배고픔/엉킴/더러움)를 주기적으로 누적하고,
	클라이언트의 케어 요청(먹이주기/빗어주기/목욕시키기)을 검증하여 처리합니다.

	[욕구 누적 루프]
	  - init() 에서 task.spawn 무한 루프를 시작합니다.
	  - GameConfig.Care.tickInterval 초마다 접속 중인 모든 플레이어의 알파카 모델을 순회하여
	    Hunger/Tangle/Dirt 속성을 일정량씩 증가시키고 Happiness 를 재계산합니다.
	  - 모델 속성에 직접 SetAttribute 하므로 클라이언트로 자동 복제됩니다(별도 푸시 불필요).
	  - 시각 갱신은 AlpacaSpawner.updateVisual 을 매 틱 호출하여 처리합니다.

	[케어 처리]
	  - "RequestCare" RemoteEvent 를 수신합니다.
	  - careType(feed/brush/bath) 유효성, 근접 거리, 디바운스, 케어 필요 여부를 순서대로 검증합니다.
	  - 검증 통과 시 해당 욕구를 0 으로 초기화하고 보상 머니를 지급합니다.
	  - 수익 부스트 배수를 반영하여 최종 보상을 산정합니다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage.GameConfig)
local Remotes       = require(ReplicatedStorage.Remotes)
local DataManager   = require(script.Parent.DataManager)
local FarmService   = require(script.Parent.FarmService)
local AlpacaSpawner = require(script.Parent.AlpacaSpawner)
local AlpacaAI      = require(script.Parent.AlpacaAI)

local CareService = {}

-- 디바운스 테이블: [uid] = 마지막 케어 시각(os.clock)
local debounceMap: { [string]: number } = {}

-- 내부 헬퍼: 플레이어에게 알림 전송
local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Event("Notify"):FireClient(player, message, isError)
end

-- 욕구 누적 루프 (init 에서 task.spawn 으로 실행)
local function needAccumulateLoop()
	local tickInterval = GameConfig.Care.tickInterval
	-- tickInterval 초마다 욕구가 0→100 으로 차오르도록 1틱당 증가량 계산
	local perTick = 100 * tickInterval / GameConfig.Care.riseTime

	while true do
		task.wait(tickInterval)

		for _, player in ipairs(Players:GetPlayers()) do
			-- 데이터가 아직 로드되지 않은 플레이어는 건너뜀
			if not DataManager.isLoaded(player) then
				continue
			end

			local models = FarmService.getAlpacaModels(player)
			for _, model in ipairs(models) do
				-- 현재 욕구 값 읽기 (속성이 없을 경우 0 으로 방어)
				local h = (model:GetAttribute("Hunger")  :: number?) or 0
				local t = (model:GetAttribute("Tangle")  :: number?) or 0
				local d = (model:GetAttribute("Dirt")    :: number?) or 0

				-- 욕구 증가 (최대 100 상한)
				h = math.min(100, h + perTick)
				t = math.min(100, t + perTick)
				d = math.min(100, d + perTick)

				-- 행복도 재계산
				local happiness = GameConfig.computeHappiness(h, t, d)

				-- 모델 속성 갱신 (자동 복제 — 클라 별도 푸시 불필요)
				model:SetAttribute("Hunger",    h)
				model:SetAttribute("Tangle",    t)
				model:SetAttribute("Dirt",      d)
				model:SetAttribute("Happiness", happiness)

				-- 시각 갱신 (욕구 임계치 경계에 관계없이 매 틱 호출)
				AlpacaSpawner.updateVisual(model, h, t, d)
			end
		end
	end
end

-- 케어 요청 처리 핸들러
local function onRequestCare(player: Player, uid: unknown, careType: unknown)
	-- 기본 타입 검증
	if type(uid) ~= "string" or type(careType) ~= "string" then
		return
	end

	-- careType 유효성 검증 (GameConfig.Care.types 에 존재하는 키여야 함)
	local careInfo = GameConfig.Care.types[careType]
	if not careInfo then
		return
	end

	-- 알파카 모델 조회
	local model = FarmService.getModelByUid(player, uid)
	if not model then
		return
	end

	-- 근접 거리 검증
	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local distance = (hrp.Position - model:GetPivot().Position).Magnitude
	if distance > GameConfig.Care.proximity then
		-- 너무 멀리 있으면 무시 (클라 핑 차이로 인한 오차는 서버 판정 우선)
		return
	end

	-- 디바운스 검증: 마지막 케어로부터 actionDebounce 초 이내면 무시
	local now = os.clock()
	local lastTime = debounceMap[uid]
	if lastTime ~= nil and (now - lastTime) < GameConfig.Care.actionDebounce then
		return
	end
	debounceMap[uid] = now

	-- 케어 필요 여부 검증
	local needKey = careInfo.need  -- "Hunger" / "Tangle" / "Dirt"
	local currentNeed = (model:GetAttribute(needKey) :: number?) or 0
	if currentNeed < GameConfig.Care.careThreshold then
		notify(player, "아직 케어가 필요하지 않아요.", false)
		return
	end

	-- 검증 통과: 해당 욕구 속성 초기화
	model:SetAttribute(needKey, 0)

	-- 초기화 후 나머지 욕구 값으로 행복도 재계산
	local h = (model:GetAttribute("Hunger")  :: number?) or 0
	local t = (model:GetAttribute("Tangle")  :: number?) or 0
	local d = (model:GetAttribute("Dirt")    :: number?) or 0
	local happiness = GameConfig.computeHappiness(h, t, d)
	model:SetAttribute("Happiness", happiness)

	-- 시각 갱신
	AlpacaSpawner.updateVisual(model, h, t, d)

	-- 보상 계산
	local alpacaId = model:GetAttribute("AlpacaId") :: string?
	if not alpacaId then
		return
	end
	local def = GameConfig.AlpacasById[alpacaId]
	if not def then
		return
	end
	local mult = (DataManager.hasIncomeBoost(player) and GameConfig.Monetization.incomeBoost.multiplier) or 1
	local reward = math.floor(def.careReward * mult * GameConfig.Economy.moneyMultiplier)

	DataManager.addMoney(player, reward)
	DataManager.incrementCareCount(player)

	-- 케어 피드백 전송
	Remotes.Event("CareFeedback"):FireClient(player, uid, careType, reward)
	-- 케어받은 알파카가 행복 반응(점프·소리 등)을 하도록 AlpacaAI 에 위임
	AlpacaAI.reactToCare(model, careType, player)
end

-- 모듈 초기화: 루프 시작 및 RemoteEvent 연결
function CareService.init()
	-- 욕구 누적 루프를 별도 스레드에서 시작
	task.spawn(needAccumulateLoop)

	-- 케어 요청 이벤트 연결
	Remotes.Event("RequestCare").OnServerEvent:Connect(onRequestCare)
end

return CareService
