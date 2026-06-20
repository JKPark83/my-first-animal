--!strict
--[[
	AlpacaShopService
	-----------------
	알파카 구매 및 농장 슬롯 확장을 담당하는 서버 서비스.

	- RequestBuyAlpaca  : 클라이언트 구매 요청 수신 → 통화 종류·슬롯 여유·잔액 검증
	                      → DataManager(데이터) / FarmService(모델) / CollectionService(도감) 에 반영.
	- RequestExpandSlot : 슬롯 확장 요청 수신 → 최대치 및 잔액 확인 → 슬롯 추가.

	검증 실패 시 Remotes.Event("Notify") 로 클라이언트에 오류 메시지를 전달합니다.
	Robux 알파카 구매는 GamePassService 가 담당하므로 이 서비스에서 처리하지 않습니다.
]]

local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataManager = require(script.Parent.DataManager)
local FarmService = require(script.Parent.FarmService)
local CollectionService = require(script.Parent.CollectionService)
local AlpacaSpawner = require(script.Parent.AlpacaSpawner)

local AlpacaShopService = {}

-- =====================================================================
-- 내부 헬퍼
-- =====================================================================

-- 클라이언트에 일반/오류 알림을 전송합니다.
local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Event("Notify"):FireClient(player, message, isError)
end

-- =====================================================================
-- init : Remote 이벤트 연결
-- =====================================================================
function AlpacaShopService.init()

	-- ------------------------------------------------------------------
	-- RequestBuyAlpaca : 알파카 구매 처리
	-- ------------------------------------------------------------------
	Remotes.Event("RequestBuyAlpaca").OnServerEvent:Connect(function(player: Player, defId: unknown)
		-- 데이터 로드 확인
		if not DataManager.isLoaded(player) then
			return
		end

		-- defId 타입 방어
		if type(defId) ~= "string" then
			notify(player, "잘못된 요청입니다.", true)
			return
		end

		-- GameConfig 에서 알파카 정의 조회
		local def = GameConfig.AlpacasById[defId]
		if not def then
			notify(player, "존재하지 않는 알파카입니다.", true)
			return
		end

		-- 통화 확인: Robux 알파카는 GamePassService 담당
		if def.currency ~= "Money" then
			notify(player, "로벅스 알파카는 가게에서 구매할 수 없습니다.", true)
			return
		end

		-- 슬롯 여유 확인
		local currentAlpacas = DataManager.getAlpacas(player)
		local currentSlots = DataManager.getSlots(player)
		if #currentAlpacas >= currentSlots then
			notify(player, "농장 슬롯이 가득 찼어요! 슬롯을 확장하세요.", true)
			return
		end

		-- 잔액 확인
		if DataManager.getMoney(player) < def.price then
			notify(player, "돈이 부족해요.", true)
			return
		end

		-- ---- 구매 처리 ----
		local uid = HttpService:GenerateGUID(false)
		local record = {
			uid = uid,
			defId = defId,
			hunger = 0,
			tangle = 0,
			dirt = 0,
			happiness = 100,
			wool = 0,
		}

		-- 금액 차감 (경쟁 조건 방어: 직전에 잔액이 바뀐 경우 addMoney 가 false 반환)
		local moneyOk = DataManager.addMoney(player, -def.price)
		if not moneyOk then
			notify(player, "돈이 부족해요.", true)
			return
		end

		-- 알파카 데이터 추가 (슬롯 초과 시 false 반환 → 환불)
		local alpacaOk = DataManager.addAlpaca(player, record)
		if not alpacaOk then
			DataManager.addMoney(player, def.price) -- 환불
			notify(player, "농장 슬롯이 가득 찼어요! 슬롯을 확장하세요.", true)
			return
		end

		-- 농장에 알파카 모델 스폰
		FarmService.spawnAlpaca(player, record)

		-- 도감 등록
		CollectionService.register(player, defId)

		-- 클라이언트에 이름짓기 모달 요청 (방금 입양한 알파카 uid)
		Remotes.Event("PromptNameAlpaca"):FireClient(player, uid, defId, def.displayName)

		-- 완료 알림
		notify(player, def.displayName .. " 입양 완료! 🦙")
	end)

	-- ------------------------------------------------------------------
	-- RequestNameAlpaca : 알파카 별명 설정 (구매 직후 입력 또는 변경)
	-- ------------------------------------------------------------------
	Remotes.Event("RequestNameAlpaca").OnServerEvent:Connect(function(player: Player, uid: unknown, rawName: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(uid) ~= "string" or type(rawName) ~= "string" then
			return
		end
		local rec = DataManager.getAlpacaByUid(player, uid)
		if not rec then
			return -- 본인 소유 알파카가 아니면 무시
		end

		-- 앞뒤 공백 제거
		local name = (rawName:gsub("^%s+", ""):gsub("%s+$", ""))
		if #name == 0 then
			return
		end
		-- 길이 제한(최대 16글자, 멀티바이트 안전)
		local len = utf8.len(name)
		if len and len > 16 then
			local byteEnd = utf8.offset(name, 17)
			if byteEnd then
				name = name:sub(1, byteEnd - 1)
			end
		end

		-- 욕설/부적절 표현 필터 (모두에게 보이는 텍스트 → Roblox 정책상 필수)
		local filtered = name
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
		end)
		if ok and type(result) == "string" and #result > 0 then
			filtered = result
		end

		-- 데이터(캐시 참조) + 모델 이름표 갱신
		rec.name = filtered
		local model = FarmService.getModelByUid(player, uid)
		if model then
			AlpacaSpawner.setNickname(model, filtered)
		end
		DataManager.pushToClient(player)
		task.spawn(DataManager.save, player) -- 즉시 영구 저장(실패해도 자동 저장이 보완)
	end)

	-- ------------------------------------------------------------------
	-- RequestExpandSlot : 농장 슬롯 확장 처리
	-- ------------------------------------------------------------------
	Remotes.Event("RequestExpandSlot").OnServerEvent:Connect(function(player: Player)
		-- 데이터 로드 확인
		if not DataManager.isLoaded(player) then
			return
		end

		-- 다음 슬롯 비용 조회 (nil = 이미 최대)
		local cost = GameConfig.getNextSlotCost(DataManager.getSlots(player))
		if cost == nil then
			notify(player, "이미 최대 슬롯이에요.", true)
			return
		end

		-- 잔액 확인
		if DataManager.getMoney(player) < cost then
			notify(player, "돈이 부족해요.", true)
			return
		end

		-- 금액 차감 (경쟁 조건 방어)
		local moneyOk = DataManager.addMoney(player, -cost)
		if not moneyOk then
			notify(player, "돈이 부족해요.", true)
			return
		end

		-- 슬롯 추가
		DataManager.addSlots(player, 1)

		-- 완료 알림 (추가 후 최신값 조회)
		notify(player, "농장 슬롯을 확장했어요! (현재 " .. DataManager.getSlots(player) .. "칸)")
	end)
end

return AlpacaShopService
