--!strict
--[[
	GamePassService
	---------------
	로벅스 게임패스(수익 2배 부스트) 관련 서버 로직을 담당합니다.

	[현재 상태]
	  - GameConfig.Monetization.enabled 가 false 이므로 실제 결제 흐름은 비활성화된 상태입니다.
	  - 클라이언트에서 "RequestBuyGamePass" 를 보내면 안내 메시지를 반환하고 조용히 종료합니다.
	  - 언제든 enabled 를 true 로 바꾸고 gamePassId 를 채우면 즉시 정상 동작합니다.

	[플레이어 로드 시]
	  - enabled 이고 gamePassId 가 유효할 때 UserOwnsGamePassAsync 로 소유 여부를 확인합니다.
	  - 이미 구매한 유저면 DataManager.setIncomeBoost 로 부스트를 활성화합니다.

	[구매 요청]
	  - "RequestBuyGamePass" RemoteEvent 를 수신합니다.
	  - passKey 가 "incomeBoost" 가 아니면 무시합니다.
	  - 비활성 상태거나 이미 보유 중이면 안내 메시지를 전송합니다.
	  - 정상 상태면 PromptGamePassPurchase 로 로벅스 구매창을 띄웁니다.

	[구매 완료 콜백]
	  - PromptGamePassPurchaseFinished 이벤트에서 결제 성공을 확인합니다.
	  - 성공하면 DataManager.setIncomeBoost(player, true) 후 완료 알림을 보냅니다.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local GameConfig  = require(ReplicatedStorage.GameConfig)
local Remotes     = require(ReplicatedStorage.Remotes)
local DataManager = require(script.Parent.DataManager)

local GamePassService = {}

-- 편의 상수: 수익 부스트 설정 단축 참조
local monetization = GameConfig.Monetization
local boostConfig  = monetization.incomeBoost

-- 내부 헬퍼: 플레이어에게 알림 전송
local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Event("Notify"):FireClient(player, message, isError)
end

-- 내부 헬퍼: 플레이어가 게임패스를 소유 중인지 안전하게 확인
local function checkOwnership(player: Player, gamePassId: number): boolean
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)
	if not ok then
		warn("[GamePassService] UserOwnsGamePassAsync 실패 (userId=" .. player.UserId .. "): " .. tostring(owns))
		return false
	end
	return owns == true
end

-- 모듈 초기화: 훅 등록 및 RemoteEvent 연결
function GamePassService.init()
	local gamePassId = boostConfig.gamePassId

	-- ──────────────────────────────────────────────────────────────
	-- 플레이어 데이터 로드 완료 시: 기존 게임패스 소유 여부 동기화
	-- ──────────────────────────────────────────────────────────────
	DataManager.onLoaded(function(player: Player)
		-- 비활성 상태이거나 gamePassId 가 미설정이면 아무것도 하지 않음
		if not monetization.enabled or gamePassId <= 0 then
			return
		end

		-- 이미 부스트가 활성화된 상태면 재확인 불필요
		if DataManager.hasIncomeBoost(player) then
			return
		end

		-- 로벅스 게임패스 소유 여부 확인 후 부스트 적용
		if checkOwnership(player, gamePassId) then
			DataManager.setIncomeBoost(player, true)
		end
	end)

	-- ──────────────────────────────────────────────────────────────
	-- 클라이언트 구매 요청: "RequestBuyGamePass"
	-- ──────────────────────────────────────────────────────────────
	Remotes.Event("RequestBuyGamePass").OnServerEvent:Connect(function(player: Player, passKey: any)
		-- "incomeBoost" 이외의 패스 키는 무시
		if passKey ~= "incomeBoost" then
			return
		end

		-- 비활성 상태 또는 gamePassId 미설정 시 안내 메시지 후 종료
		if not monetization.enabled or gamePassId <= 0 then
			notify(player, "로벅스 상점은 게임 출시 후 열려요! 🛠️", false)
			return
		end

		-- 이미 보유 중인 경우 안내 후 종료
		if DataManager.hasIncomeBoost(player) then
			notify(player, "이미 보유한 혜택이에요.", false)
			return
		end

		-- 로벅스 구매창 표시 (pcall 로 감싸 에러 방지)
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, gamePassId)
		end)
		if not ok then
			warn("[GamePassService] PromptGamePassPurchase 실패 (userId=" .. player.UserId .. "): " .. tostring(err))
		end
	end)

	-- ──────────────────────────────────────────────────────────────
	-- 구매 완료 콜백: PromptGamePassPurchaseFinished
	-- ──────────────────────────────────────────────────────────────
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, purchasedPassId: number, wasPurchased: boolean)
			-- 구매 취소 또는 다른 게임패스이면 무시
			if not wasPurchased then
				return
			end
			if purchasedPassId ~= boostConfig.gamePassId then
				return
			end

			-- 부스트 활성화 및 완료 알림
			local ok, err = pcall(function()
				DataManager.setIncomeBoost(player, true)
			end)
			if not ok then
				warn("[GamePassService] setIncomeBoost 실패 (userId=" .. player.UserId .. "): " .. tostring(err))
				return
			end

			notify(player, "황금 갈퀴 구매 완료! 수익이 2배가 됩니다. ✨", false)
		end
	)
end

return GamePassService
