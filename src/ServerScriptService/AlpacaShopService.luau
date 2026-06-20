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
local CareService = require(script.Parent.CareService)

local AlpacaShopService = {}

-- =====================================================================
-- 내부 헬퍼
-- =====================================================================

-- 클라이언트에 일반/오류 알림을 전송합니다.
local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Event("Notify"):FireClient(player, message, isError)
end

-- 추가 소비재(먹이/악세사리) 구매 자격: 알파카를 최소 minAlpacasToShop 마리 보유해야 한다.
-- (알파카 없이 돈을 다 써버려 더 이상 벌 수단이 없어지는 막다른 길 방지)
local function hasMinAlpacas(player: Player): boolean
	return #DataManager.getAlpacas(player) >= GameConfig.Economy.minAlpacasToShop
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

	-- ------------------------------------------------------------------
	-- RequestBuyFood : 먹이 구매 (인벤토리에 1개 적립)
	-- ------------------------------------------------------------------
	Remotes.Event("RequestBuyFood").OnServerEvent:Connect(function(player: Player, foodId: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(foodId) ~= "string" then
			return
		end
		local food = GameConfig.FoodsById[foodId]
		if not food then
			notify(player, "존재하지 않는 먹이예요.", true)
			return
		end
		if food.price <= 0 then
			notify(player, food.displayName .. "은(는) 기본 제공이라 구매할 필요가 없어요.", true)
			return
		end
		if not hasMinAlpacas(player) then
			notify(player, "먼저 알파카를 입양해야 먹이를 살 수 있어요. 🦙", true)
			return
		end
		if DataManager.getMoney(player) < food.price then
			notify(player, "돈이 부족해요.", true)
			return
		end
		-- 금액 차감 (경쟁 조건 방어)
		if not DataManager.addMoney(player, -food.price) then
			notify(player, "돈이 부족해요.", true)
			return
		end
		DataManager.addFood(player, foodId, 1)
		notify(player, food.emoji .. " " .. food.displayName .. " 구매! (보유 " .. DataManager.getFoodCount(player, foodId) .. "개)")
	end)

	-- ------------------------------------------------------------------
	-- RequestSelectFood : 사용할 먹이 선택
	-- ------------------------------------------------------------------
	Remotes.Event("RequestSelectFood").OnServerEvent:Connect(function(player: Player, foodId: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(foodId) ~= "string" or not GameConfig.FoodsById[foodId] then
			return
		end
		local food = GameConfig.FoodsById[foodId]
		-- 유료 먹이는 보유 중일 때만 선택 가능(기본 무료 먹이는 항상 가능)
		if food.price > 0 and DataManager.getFoodCount(player, foodId) <= 0 then
			notify(player, "먹이를 보유하고 있지 않아요. 먼저 구매하세요.", true)
			return
		end
		if DataManager.setSelectedFood(player, foodId) then
			notify(player, food.emoji .. " " .. food.displayName .. "을(를) 사용 먹이로 선택했어요.")
		end
	end)

	-- ------------------------------------------------------------------
	-- RequestBuyAccessory : 악세사리 구매 (보유 목록에 추가)
	-- ------------------------------------------------------------------
	Remotes.Event("RequestBuyAccessory").OnServerEvent:Connect(function(player: Player, accId: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(accId) ~= "string" then
			return
		end
		local acc = GameConfig.AccessoriesById[accId]
		if not acc then
			notify(player, "존재하지 않는 악세사리예요.", true)
			return
		end
		if DataManager.hasAccessory(player, accId) then
			notify(player, "이미 보유한 악세사리예요.", true)
			return
		end
		if not hasMinAlpacas(player) then
			notify(player, "먼저 알파카를 입양해야 악세사리를 살 수 있어요. 🦙", true)
			return
		end
		if DataManager.getMoney(player) < acc.price then
			notify(player, "돈이 부족해요.", true)
			return
		end
		if not DataManager.addMoney(player, -acc.price) then
			notify(player, "돈이 부족해요.", true)
			return
		end
		DataManager.addAccessory(player, accId)
		notify(player, acc.emoji .. " " .. acc.displayName .. " 구매 완료! 알파카에게 입혀보세요.")
	end)

	-- ------------------------------------------------------------------
	-- RequestEquipAccessory : 보유 악세사리를 특정 알파카에 착용/해제
	--   accId == "" 또는 nil → 벗기기
	-- ------------------------------------------------------------------
	Remotes.Event("RequestEquipAccessory").OnServerEvent:Connect(function(player: Player, uid: unknown, accId: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(uid) ~= "string" then
			return
		end
		local rec = DataManager.getAlpacaByUid(player, uid)
		if not rec then
			return -- 본인 소유 알파카가 아니면 무시
		end
		local model = FarmService.getModelByUid(player, uid)

		-- 벗기기
		if accId == nil or accId == "" then
			DataManager.setAlpacaAccessory(player, uid, nil)
			if model then
				AlpacaSpawner.applyAccessory(model, nil)
			end
			notify(player, "악세사리를 벗겼어요.")
			return
		end

		if type(accId) ~= "string" or not GameConfig.AccessoriesById[accId] then
			return
		end
		if not DataManager.hasAccessory(player, accId) then
			notify(player, "먼저 악세사리를 구매하세요.", true)
			return
		end
		DataManager.setAlpacaAccessory(player, uid, accId)
		if model then
			AlpacaSpawner.applyAccessory(model, accId)
		end
		local acc = GameConfig.AccessoriesById[accId]
		notify(player, acc.emoji .. " " .. acc.displayName .. " 착용 완료!")
	end)

	-- ------------------------------------------------------------------
	-- RequestSellFood : 보유 먹이 1개 되팔기 (원가의 sellRatio 환급)
	-- ------------------------------------------------------------------
	Remotes.Event("RequestSellFood").OnServerEvent:Connect(function(player: Player, foodId: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(foodId) ~= "string" then
			return
		end
		local food = GameConfig.FoodsById[foodId]
		if not food then
			notify(player, "존재하지 않는 먹이예요.", true)
			return
		end
		if food.price <= 0 then
			notify(player, food.displayName .. "은(는) 되팔 수 없어요.", true)
			return
		end
		if DataManager.getFoodCount(player, foodId) <= 0 then
			notify(player, "되팔 먹이가 없어요.", true)
			return
		end
		-- 1개 차감 (마지막 한 개를 소진하면 consumeFood 가 선택 먹이를 기본 먹이로 되돌린다)
		if not DataManager.consumeFood(player, foodId) then
			notify(player, "되팔 먹이가 없어요.", true)
			return
		end
		local refund = GameConfig.sellPrice(food.price)
		DataManager.addMoney(player, refund)
		notify(
			player,
			food.emoji .. " " .. food.displayName .. " 되팔기! +💰" .. refund
				.. " (보유 " .. DataManager.getFoodCount(player, foodId) .. "개)"
		)
	end)

	-- ------------------------------------------------------------------
	-- RequestSellAccessory : 보유 악세사리 되팔기 (착용 중이면 자동 해제)
	-- ------------------------------------------------------------------
	Remotes.Event("RequestSellAccessory").OnServerEvent:Connect(function(player: Player, accId: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(accId) ~= "string" then
			return
		end
		local acc = GameConfig.AccessoriesById[accId]
		if not acc then
			notify(player, "존재하지 않는 악세사리예요.", true)
			return
		end
		if not DataManager.hasAccessory(player, accId) then
			notify(player, "보유하지 않은 악세사리예요.", true)
			return
		end
		-- 보유 제거 + 착용 중이던 알파카들 자동 해제 → 영향받은 모델 외형 갱신
		local affected = DataManager.removeAccessory(player, accId)
		for _, uid in ipairs(affected) do
			local model = FarmService.getModelByUid(player, uid)
			if model then
				AlpacaSpawner.applyAccessory(model, nil)
			end
		end
		local refund = GameConfig.sellPrice(acc.price)
		DataManager.addMoney(player, refund)
		notify(player, acc.emoji .. " " .. acc.displayName .. " 되팔기! +💰" .. refund)
	end)

	-- ------------------------------------------------------------------
	-- RequestSellAlpaca : 알파카 되팔기 (모델/데이터 제거, 슬롯 회수, 원가 80% 환급)
	--   ⚠ 도감 기록은 유지(한 번이라도 보유했으면 발견으로 인정).
	--   ⚠ 미수집 양털은 함께 사라지므로 클라 측에서 판매 전 확인을 받는다.
	-- ------------------------------------------------------------------
	Remotes.Event("RequestSellAlpaca").OnServerEvent:Connect(function(player: Player, uid: unknown)
		if not DataManager.isLoaded(player) then
			return
		end
		if type(uid) ~= "string" then
			return
		end
		local rec = DataManager.getAlpacaByUid(player, uid)
		if not rec then
			return -- 본인 소유 알파카가 아니면 무시
		end
		local def = GameConfig.AlpacasById[rec.defId]
		local refund = def and GameConfig.sellPrice(def.price) or 0
		local name = (rec.name and rec.name ~= "" and rec.name) or (def and def.displayName) or "알파카"

		-- 데이터 제거 → 모델 제거(슬롯 회수) → 디바운스 정리
		DataManager.removeAlpaca(player, uid)
		FarmService.removeAlpacaModel(player, uid)
		CareService.clearDebounce(uid)

		if refund > 0 then
			DataManager.addMoney(player, refund)
		end
		notify(player, "👋 " .. name .. " 판매 완료! +💰" .. refund)
	end)
end

return AlpacaShopService
