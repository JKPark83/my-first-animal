--!strict
--[[
	WoolService
	-----------
	양털 관련 서버 로직을 담당합니다.

	[패시브 적립 루프]
	  - init() 에서 task.spawn 무한 루프를 시작합니다.
	  - GameConfig.Wool.cycle 초마다 접속 중인 모든 플레이어의 알파카 모델을 순회하여
	    행복도(Happiness)에 비례한 양털(Wool)을 모델 속성에 적립합니다.
	  - 모델 속성에 직접 SetAttribute 하므로 클라이언트로 자동 복제됩니다.
	  - GameConfig.Wool.autoCollect 가 true 일 때 즉시 머니화하는 분기가 준비되어 있습니다
	    (현재 false 이므로 실제 실행되지 않습니다).

	[양털 수집]
	  - "RequestCollectWool" RemoteEvent 를 수신합니다.
	  - uid(string) 이면 해당 알파카 1마리, nil 이면 플레이어 전체 알파카를 수집합니다.
	  - 수집 금액에 수익 부스트 배수를 적용한 뒤 DataManager.addMoney 로 지급합니다.
	  - 수집 결과는 "WoolCollected" RemoteEvent 로 클라이언트에 알립니다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes   = require(ReplicatedStorage.Remotes)
local DataManager = require(script.Parent.DataManager)
local FarmService = require(script.Parent.FarmService)

local WoolService = {}

-- 내부 헬퍼: 플레이어에게 알림 전송
local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Event("Notify"):FireClient(player, message, isError)
end

-- 내부 헬퍼: 수익 부스트 배수 반환
local function getIncomeMult(player: Player): number
	return (DataManager.hasIncomeBoost(player) and GameConfig.Monetization.incomeBoost.multiplier) or 1
end

-- 패시브 양털 적립 루프 (init 에서 task.spawn 으로 실행)
local function woolAccumulateLoop()
	while true do
		task.wait(GameConfig.Wool.cycle)

		for _, player in ipairs(Players:GetPlayers()) do
			-- 데이터가 아직 로드되지 않은 플레이어는 건너뜀
			if not DataManager.isLoaded(player) then
				continue
			end

			local models = FarmService.getAlpacaModels(player)
			for _, model in ipairs(models) do
				-- 알파카 정의 조회
				local alpacaId = model:GetAttribute("AlpacaId")
				if type(alpacaId) ~= "string" then
					continue
				end
				local def = GameConfig.AlpacasById[alpacaId]
				if not def then
					continue
				end

				-- 행복도 기반 적립 배수 계산
				local happiness = (model:GetAttribute("Happiness") or 100) :: number
				local happinessFactor = math.clamp(happiness / 100, 0, 1)
				local multiplier = GameConfig.Wool.minMultiplier
					+ (1 - GameConfig.Wool.minMultiplier) * happinessFactor

				-- 적립량 및 상한선 계산 (전역 수익 배수 incomeMultiplier 적용)
				local gain    = def.woolValue * multiplier * GameConfig.Wool.incomeMultiplier
				local cap     = def.woolValue * GameConfig.Wool.capCycles
				local current = (model:GetAttribute("Wool") or 0) :: number
				local newWool = math.min(current + gain, cap)

				model:SetAttribute("Wool", newWool)

				-- autoCollect 가 활성화된 경우 즉시 머니화 (현재 false 라 실행되지 않음)
				if GameConfig.Wool.autoCollect then
					local earned = math.floor(newWool)
					if earned > 0 then
						local mult = getIncomeMult(player)
						local amount = math.floor(earned * mult)
						DataManager.addMoney(player, amount)
						model:SetAttribute("Wool", newWool - earned)
					end
				end
			end
		end
	end
end

-- 양털 수집 처리: uid(string) 이면 1마리, nil 이면 전체
local function handleCollectWool(player: Player, uid: any)
	-- 타입 방어: uid 는 string 또는 nil 만 허용
	if uid ~= nil and type(uid) ~= "string" then
		notify(player, "잘못된 요청입니다.", true)
		return
	end

	if not DataManager.isLoaded(player) then
		notify(player, "데이터를 불러오는 중입니다. 잠시 후 다시 시도해 주세요.", true)
		return
	end

	local mult = getIncomeMult(player)
	local total = 0

	if type(uid) == "string" then
		-- 특정 알파카 1마리 수집
		local model = FarmService.getModelByUid(player, uid)
		if not model then
			notify(player, "해당 알파카를 찾을 수 없습니다.", true)
			-- 수집량 0 으로 클라에 알림 (클라가 "적립된 양털이 없어요" 처리)
			Remotes.Event("WoolCollected"):FireClient(player, 0)
			return
		end
		local wool = (model:GetAttribute("Wool") or 0) :: number
		total = total + math.floor(wool)
		model:SetAttribute("Wool", 0)
	else
		-- 플레이어 전체 알파카 수집
		local models = FarmService.getAlpacaModels(player)
		for _, model in ipairs(models) do
			local wool = (model:GetAttribute("Wool") or 0) :: number
			total = total + math.floor(wool)
			model:SetAttribute("Wool", 0)
		end
	end

	-- 부스트 배수 적용 후 지급
	local amount = math.floor(total * mult)
	if amount > 0 then
		DataManager.addMoney(player, amount)
	end

	-- 수집 결과를 클라이언트에 전달 (0 이어도 전송해 클라가 피드백 표시 가능)
	Remotes.Event("WoolCollected"):FireClient(player, amount)
end

-- 모듈 초기화: RemoteEvent 연결 및 적립 루프 시작
function WoolService.init()
	-- 양털 수집 요청 수신
	Remotes.Event("RequestCollectWool").OnServerEvent:Connect(handleCollectWool)

	-- 패시브 적립 루프를 별도 스레드에서 시작
	task.spawn(woolAccumulateLoop)
end

return WoolService
