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

-- 알파카가 제거(판매/사망)될 때 디바운스 항목을 정리한다(메모리 누수 방지).
-- 다른 서비스(예: 알파카 판매)에서 호출한다. uid 는 GUID 라 재사용되지 않으므로 안전.
function CareService.clearDebounce(uid: string)
	debounceMap[uid] = nil
end

-- 알파카 표시 이름 (별명 우선, 없으면 종 이름)
local function displayNameOf(model: Model): string
	local nick = model:GetAttribute("Nickname") :: string?
	if nick and nick ~= "" then
		return nick
	end
	local alpacaId = model:GetAttribute("AlpacaId") :: string?
	local def = alpacaId and GameConfig.AlpacasById[alpacaId]
	return (def and def.displayName) or "알파카"
end

-- 굶주림 사망 연출: 모델 위치에 잠깐 빌보드를 띄웠다가 사라지게 함
local function spawnDeathPoof(model: Model)
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if not ok then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = pivot + Vector3.new(0, 3, 0)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 3)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "💀 떠났어요…"
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0.2
	lbl.Parent = gui

	game:GetService("Debris"):AddItem(anchor, 2.5)
end

-- 굶주림 사망 처리: 연출 + 데이터/모델 제거(슬롯 비움) + 알림
local function handleStarveDeath(player: Player, model: Model)
	local uid = model:GetAttribute("Uid") :: string?
	local name = displayNameOf(model)
	spawnDeathPoof(model)
	if uid then
		DataManager.removeAlpaca(player, uid)
		debounceMap[uid] = nil
	end
	model:Destroy()
	notify(player, "😢 " .. name .. "(이)가 굶주려 떠났어요… 먹이를 제때 주세요!", true)
end

-- 먹이주기 효과 적용: 선택한 먹이를 1개 소비하고 효과(추가 정돈·양털 보너스)를 적용한다.
-- 인벤토리가 비면 기본 먹이로 대체. 반환값은 케어 보상 배수.
local function applyFeedFood(player: Player, model: Model, def: any): number
	local selected = DataManager.getSelectedFood(player)
	local foodDef = GameConfig.FoodsById[selected] or GameConfig.FoodsById[GameConfig.DefaultFood]
	-- 기본 먹이가 아니면 재고 1개 소비, 소진 시 기본 먹이로 대체
	if foodDef and foodDef.id ~= GameConfig.DefaultFood then
		if not DataManager.consumeFood(player, foodDef.id) then
			foodDef = GameConfig.FoodsById[GameConfig.DefaultFood]
		end
	end
	if not foodDef then
		return 1
	end
	-- 추가 정돈: 엉킴/더러움 함께 감소
	if foodDef.extraClean > 0 then
		local t = (model:GetAttribute("Tangle") :: number?) or 0
		local d = (model:GetAttribute("Dirt") :: number?) or 0
		model:SetAttribute("Tangle", math.max(0, t - foodDef.extraClean))
		model:SetAttribute("Dirt", math.max(0, d - foodDef.extraClean))
	end
	-- 양털 보너스: 즉시 적립(상한 적용)
	if foodDef.woolBonus > 0 then
		local cur = (model:GetAttribute("Wool") :: number?) or 0
		local cap = def.woolValue * GameConfig.Wool.capCycles
		model:SetAttribute("Wool", math.min(cap, cur + foodDef.woolBonus))
	end
	return foodDef.rewardMult
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

				-- 굶주림(먹이 안 줌) 사망/경고 체크 — "Fed"(마지막 먹인 시각) 기준
				local fedAt = model:GetAttribute("Fed") :: number?
				if not fedAt then
					-- 구버전 모델 방어: 기준 시각이 없으면 지금으로 초기화
					model:SetAttribute("Fed", os.time())
				else
					local starved = os.time() - fedAt
					if starved >= GameConfig.Care.starveDeathTime then
						handleStarveDeath(player, model)
						continue
					elseif starved >= GameConfig.Care.starveWarnTime and model:GetAttribute("StarveWarned") ~= true then
						model:SetAttribute("StarveWarned", true)
						notify(
							player,
							"🦙 " .. displayNameOf(model) .. "(이)가 너무 배고파요! 먹이를 주지 않으면 곧 떠나요.",
							true
						)
					end
				end
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

	-- 보상 계산용 종 정보 먼저 확보
	local alpacaId = model:GetAttribute("AlpacaId") :: string?
	if not alpacaId then
		return
	end
	local def = GameConfig.AlpacasById[alpacaId]
	if not def then
		return
	end

	-- 먹이주기: 선택한 먹이 소비 + 효과 적용 + 굶주림 사망 타이머 리셋
	local foodMult = 1
	if careType == "feed" then
		foodMult = applyFeedFood(player, model, def)
		model:SetAttribute("Fed", os.time())
		model:SetAttribute("StarveWarned", false)
	end

	-- (먹이 효과로 Tangle/Dirt 가 바뀌었을 수 있으니) 최신 값으로 행복도 재계산
	local h = (model:GetAttribute("Hunger")  :: number?) or 0
	local t = (model:GetAttribute("Tangle")  :: number?) or 0
	local d = (model:GetAttribute("Dirt")    :: number?) or 0
	local happiness = GameConfig.computeHappiness(h, t, d)
	model:SetAttribute("Happiness", happiness)

	-- 시각 갱신
	AlpacaSpawner.updateVisual(model, h, t, d)

	-- 보상 계산 (먹이 보상 배수 foodMult 반영 — 먹이주기에만 1 이외 값)
	local mult = (DataManager.hasIncomeBoost(player) and GameConfig.Monetization.incomeBoost.multiplier) or 1
	local reward = math.floor(def.careReward * mult * GameConfig.Economy.moneyMultiplier * foodMult)

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

	-- 퇴장 플레이어의 알파카 디바운스 항목 정리(장기 운영 시 메모리 누수 방지).
	-- DataManager.init() 이 가장 마지막에 연결되므로 이 시점엔 캐시(getAlpacas)가 아직 살아있다.
	Players.PlayerRemoving:Connect(function(player)
		for _, rec in ipairs(DataManager.getAlpacas(player)) do
			debounceMap[rec.uid] = nil
		end
	end)
end

return CareService
