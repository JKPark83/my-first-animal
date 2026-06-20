--!strict
--[[
	DataManager
	------------
	플레이어 데이터의 영구 저장을 담당합니다(참고: my-first-cargame 의 DataManager).
	- 머니 / 농장 슬롯 수 / 보유 알파카(상태 포함) / 도감 / 부스트를 DataStore에 저장
	- 접속 시 로드(재시도 포함), 퇴장·자동·서버종료 시 저장
	- 세션 캐시로 잦은 DataStore 호출을 줄임
	- onLoaded / onBeforeSave 콜백 훅으로 FarmService 등과 결합(순환 require 회피)

	다른 서버 모듈은 이 모듈의 API만 사용해 데이터를 다룹니다.

	데이터 모델(PlayerData):
		money      : number
		slots      : number  (현재 농장 슬롯 수)
		alpacas    : { AlpacaRecord }  (보유 알파카, 상태 포함)
		dex        : { [defId]: boolean }  (한 번이라도 보유한 종)
		boosts     : { incomeBoost: boolean }
		stats      : { totalEarned: number, careCount: number }

	AlpacaRecord:
		uid        : string  (고유 인스턴스 id)
		defId      : string  (GameConfig.AlpacasById 키)
		hunger     : number  0~100
		tangle     : number  0~100
		dirt       : number  0~100
		happiness  : number  0~100
		wool       : number  (적립된 양털 머니)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataManager = {}

local STORE_NAME = "AlpacaFarm_v1"
local AUTOSAVE_INTERVAL = 120 -- 초
local MAX_RETRIES = 4

-- Studio에서 API 접근이 막혀있을 수 있으므로 pcall로 감쌈
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataManager] DataStore 사용 불가 (Studio API 설정 확인). 세션 임시 저장으로 동작합니다.")
	end
end

export type AlpacaRecord = {
	uid: string,
	defId: string,
	hunger: number,
	tangle: number,
	dirt: number,
	happiness: number,
	wool: number,
	name: string?, -- 플레이어가 지은 별명(없으면 종 이름 표시)
	accessory: string?, -- 착용 중인 악세사리 id(없으면 nil)
}

export type PlayerData = {
	money: number,
	slots: number,
	alpacas: { AlpacaRecord },
	dex: { [string]: boolean },
	boosts: { incomeBoost: boolean },
	stats: { totalEarned: number, careCount: number },
	foods: { [string]: number }, -- 보유 먹이 개수 (foodId → 수량)
	selectedFood: string, -- 현재 사용할 먹이 id
	accessories: { [string]: boolean }, -- 보유 악세사리 (accId → true)
}

-- 세션 캐시: userId -> PlayerData
local cache: { [number]: PlayerData } = {}
local loaded: { [number]: boolean } = {}

-- 결합 훅
local loadedCallbacks: { (player: Player) -> () } = {}
local beforeSaveCallbacks: { (player: Player) -> () } = {}

-- =====================================================================
-- 기본 데이터 / 검증
-- =====================================================================
local function defaultData(): PlayerData
	return {
		money = GameConfig.Economy.startingMoney,
		slots = GameConfig.Economy.startingSlots,
		alpacas = {},
		dex = {},
		boosts = { incomeBoost = false },
		stats = { totalEarned = 0, careCount = 0 },
		foods = {},
		selectedFood = GameConfig.DefaultFood,
		accessories = {},
	}
end

local function reconcileAlpaca(raw: any): AlpacaRecord?
	if type(raw) ~= "table" then
		return nil
	end
	if type(raw.defId) ~= "string" or not GameConfig.AlpacasById[raw.defId] then
		return nil
	end
	local uid = type(raw.uid) == "string" and raw.uid or nil
	if not uid then
		return nil
	end
	local function num(v: any, default: number, min: number, max: number): number
		local n = tonumber(v)
		if not n then
			return default
		end
		return math.clamp(n, min, max)
	end
	return {
		uid = uid,
		defId = raw.defId,
		hunger = num(raw.hunger, 0, 0, 100),
		tangle = num(raw.tangle, 0, 0, 100),
		dirt = num(raw.dirt, 0, 0, 100),
		happiness = num(raw.happiness, 100, 0, 100),
		wool = math.max(0, tonumber(raw.wool) or 0),
		name = (type(raw.name) == "string" and raw.name ~= "" and raw.name) or nil,
		accessory = (type(raw.accessory) == "string" and GameConfig.AccessoriesById[raw.accessory] and raw.accessory)
			or nil,
	}
end

-- 저장된 데이터가 손상/구버전이어도 안전하도록 기본값과 병합
local function reconcile(raw: any): PlayerData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.money) == "number" then
		data.money = math.max(0, math.floor(raw.money))
	end
	if type(raw.slots) == "number" then
		data.slots = math.clamp(math.floor(raw.slots), GameConfig.Economy.startingSlots, GameConfig.Economy.maxSlots)
	end
	if type(raw.alpacas) == "table" then
		for _, a in ipairs(raw.alpacas) do
			local rec = reconcileAlpaca(a)
			if rec then
				data.alpacas[#data.alpacas + 1] = rec
			end
		end
	end
	if type(raw.dex) == "table" then
		for id, v in pairs(raw.dex) do
			if GameConfig.AlpacasById[id] and v == true then
				data.dex[id] = true
			end
		end
	end
	if type(raw.boosts) == "table" then
		data.boosts.incomeBoost = raw.boosts.incomeBoost == true
	end
	if type(raw.stats) == "table" then
		data.stats.totalEarned = tonumber(raw.stats.totalEarned) or 0
		data.stats.careCount = tonumber(raw.stats.careCount) or 0
	end
	if type(raw.foods) == "table" then
		for id, qty in pairs(raw.foods) do
			local n = tonumber(qty)
			if GameConfig.FoodsById[id] and n and n > 0 then
				data.foods[id] = math.floor(n)
			end
		end
	end
	-- 저장된 선택 먹이는 (1) 존재하는 먹이이고 (2) 기본 무료 먹이거나 실제 보유 중일 때만 인정.
	-- 그렇지 않으면 defaultData 의 DefaultFood 를 유지해 '보유 0 + 사용 중' 어긋남을 막는다.
	if type(raw.selectedFood) == "string" and GameConfig.FoodsById[raw.selectedFood]
		and (raw.selectedFood == GameConfig.DefaultFood or (data.foods[raw.selectedFood] or 0) > 0)
	then
		data.selectedFood = raw.selectedFood
	end
	if type(raw.accessories) == "table" then
		for id, v in pairs(raw.accessories) do
			if GameConfig.AccessoriesById[id] and v == true then
				data.accessories[id] = true
			end
		end
	end
	return data
end

-- =====================================================================
-- 로드 / 저장
-- =====================================================================
local function loadData(player: Player)
	local userId = player.UserId
	local data: PlayerData

	if store then
		local key = "u_" .. userId
		local attempt = 0
		local raw = nil
		local success = false
		while attempt < MAX_RETRIES and not success do
			attempt += 1
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(key)
			end)
			if ok then
				success = true
				raw = result
			else
				warn(("[DataManager] 로드 실패(%d/%d) %s: %s"):format(attempt, MAX_RETRIES, player.Name, tostring(result)))
				task.wait(2 ^ attempt)
			end
		end
		data = reconcile(raw)
	else
		data = defaultData()
	end

	cache[userId] = data
	loaded[userId] = true
	DataManager.pushToClient(player)

	-- onLoaded 훅 실행 (FarmService 가 농장/무리 스폰)
	for _, cb in ipairs(loadedCallbacks) do
		task.spawn(cb, player)
	end
end

function DataManager.save(player: Player): boolean
	local userId = player.UserId
	local data = cache[userId]
	if not data then
		return false
	end

	-- onBeforeSave 훅 (FarmService 가 모델 상태 → 데이터 동기화)
	for _, cb in ipairs(beforeSaveCallbacks) do
		local ok, err = pcall(cb, player)
		if not ok then
			warn("[DataManager] onBeforeSave 콜백 오류: " .. tostring(err))
		end
	end

	if not store then
		return false
	end

	local key = "u_" .. userId
	local attempt = 0
	while attempt < MAX_RETRIES do
		attempt += 1
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function()
				return data
			end)
		end)
		if ok then
			return true
		else
			warn(("[DataManager] 저장 실패(%d/%d) %s: %s"):format(attempt, MAX_RETRIES, player.Name, tostring(err)))
			task.wait(2 ^ attempt)
		end
	end
	return false
end

-- =====================================================================
-- 훅 등록
-- =====================================================================
function DataManager.onLoaded(fn: (player: Player) -> ())
	loadedCallbacks[#loadedCallbacks + 1] = fn
end

function DataManager.onBeforeSave(fn: (player: Player) -> ())
	beforeSaveCallbacks[#beforeSaveCallbacks + 1] = fn
end

-- =====================================================================
-- 조회
-- =====================================================================
function DataManager.get(player: Player): PlayerData?
	return cache[player.UserId]
end

function DataManager.isLoaded(player: Player): boolean
	return loaded[player.UserId] == true
end

function DataManager.getMoney(player: Player): number
	local data = cache[player.UserId]
	return data and data.money or 0
end

function DataManager.getSlots(player: Player): number
	local data = cache[player.UserId]
	return data and data.slots or GameConfig.Economy.startingSlots
end

function DataManager.getAlpacas(player: Player): { AlpacaRecord }
	local data = cache[player.UserId]
	return data and data.alpacas or {}
end

function DataManager.getAlpacaByUid(player: Player, uid: string): AlpacaRecord?
	local data = cache[player.UserId]
	if not data then
		return nil
	end
	for _, rec in ipairs(data.alpacas) do
		if rec.uid == uid then
			return rec
		end
	end
	return nil
end

-- 총자산 = 머니 + 보유 알파카 가격 합 + 미수집 양털 (리더보드용)
function DataManager.netWorth(player: Player): number
	local data = cache[player.UserId]
	if not data then
		return 0
	end
	local total = data.money
	for _, rec in ipairs(data.alpacas) do
		local def = GameConfig.AlpacasById[rec.defId]
		if def then
			total += def.price
		end
		total += rec.wool
	end
	return math.floor(total)
end

-- =====================================================================
-- 클라이언트 동기화
-- =====================================================================
function DataManager.pushToClient(player: Player)
	local data = cache[player.UserId]
	if data then
		Remotes.Event("PlayerDataUpdated"):FireClient(player, data)
	end
end

-- =====================================================================
-- 변경 API (모두 서버 권위)
-- =====================================================================
-- 머니 증감 (음수 가능). 성공 여부 반환. 양수면 누적 수익 통계도 갱신.
function DataManager.addMoney(player: Player, amount: number): boolean
	local data = cache[player.UserId]
	if not data then
		return false
	end
	if data.money + amount < 0 then
		return false
	end
	data.money += amount
	if amount > 0 then
		data.stats.totalEarned += amount
	end
	DataManager.pushToClient(player)
	return true
end

-- 슬롯 n칸 추가 (최대치 제한). 성공 여부 반환.
function DataManager.addSlots(player: Player, n: number): boolean
	local data = cache[player.UserId]
	if not data then
		return false
	end
	local newSlots = math.min(GameConfig.Economy.maxSlots, data.slots + n)
	if newSlots == data.slots then
		return false
	end
	data.slots = newSlots
	DataManager.pushToClient(player)
	return true
end

-- 알파카 레코드 추가. 슬롯 초과면 false.
function DataManager.addAlpaca(player: Player, record: AlpacaRecord): boolean
	local data = cache[player.UserId]
	if not data then
		return false
	end
	if #data.alpacas >= data.slots then
		return false
	end
	data.alpacas[#data.alpacas + 1] = record
	DataManager.pushToClient(player)
	return true
end

-- 알파카 제거 (uid 기준).
function DataManager.removeAlpaca(player: Player, uid: string): boolean
	local data = cache[player.UserId]
	if not data then
		return false
	end
	for i, rec in ipairs(data.alpacas) do
		if rec.uid == uid then
			table.remove(data.alpacas, i)
			DataManager.pushToClient(player)
			return true
		end
	end
	return false
end

-- 알파카 상태 갱신(케어/양털/배회 후 모델 → 데이터 동기화용). 클라 푸시는 하지 않음(잦음).
function DataManager.syncAlpacaState(player: Player, uid: string, state: { [string]: number })
	local rec = DataManager.getAlpacaByUid(player, uid)
	if not rec then
		return
	end
	if state.hunger then
		rec.hunger = math.clamp(state.hunger, 0, 100)
	end
	if state.tangle then
		rec.tangle = math.clamp(state.tangle, 0, 100)
	end
	if state.dirt then
		rec.dirt = math.clamp(state.dirt, 0, 100)
	end
	if state.happiness then
		rec.happiness = math.clamp(state.happiness, 0, 100)
	end
	if state.wool then
		rec.wool = math.max(0, state.wool)
	end
end

-- 도감 등록. 새로 등록되면 true 반환.
function DataManager.markDex(player: Player, defId: string): boolean
	local data = cache[player.UserId]
	if not data or not GameConfig.AlpacasById[defId] then
		return false
	end
	if data.dex[defId] then
		return false
	end
	data.dex[defId] = true
	DataManager.pushToClient(player)
	return true
end

function DataManager.getDexCount(player: Player): number
	local data = cache[player.UserId]
	if not data then
		return 0
	end
	local count = 0
	for defId, v in pairs(data.dex) do
		local def = GameConfig.AlpacasById[defId]
		if v and def and def.countInDex then
			count += 1
		end
	end
	return count
end

-- 부스트 설정(게임패스). 변경되면 클라 푸시.
function DataManager.setIncomeBoost(player: Player, value: boolean)
	local data = cache[player.UserId]
	if not data then
		return
	end
	if data.boosts.incomeBoost ~= value then
		data.boosts.incomeBoost = value
		DataManager.pushToClient(player)
	end
end

function DataManager.hasIncomeBoost(player: Player): boolean
	local data = cache[player.UserId]
	return data ~= nil and data.boosts.incomeBoost == true
end

-- 케어 횟수 통계
function DataManager.incrementCareCount(player: Player)
	local data = cache[player.UserId]
	if data then
		data.stats.careCount += 1
	end
end

-- =====================================================================
-- 먹이 인벤토리
-- =====================================================================
function DataManager.getFoods(player: Player): { [string]: number }
	local data = cache[player.UserId]
	return (data and data.foods) or {}
end

function DataManager.getFoodCount(player: Player, foodId: string): number
	local data = cache[player.UserId]
	return (data and data.foods[foodId]) or 0
end

function DataManager.getSelectedFood(player: Player): string
	local data = cache[player.UserId]
	return (data and data.selectedFood) or GameConfig.DefaultFood
end

-- 먹이 n개 추가. 성공 여부 반환. (가격/머니 검증은 상점 서비스에서 처리)
function DataManager.addFood(player: Player, foodId: string, qty: number): boolean
	local data = cache[player.UserId]
	if not data or not GameConfig.FoodsById[foodId] or qty <= 0 then
		return false
	end
	data.foods[foodId] = (data.foods[foodId] or 0) + math.floor(qty)
	DataManager.pushToClient(player)
	return true
end

-- 먹이 1개 소비. 재고가 있으면 차감 후 true, 없으면 false.
-- 기본 먹이(grass 등 price 0)는 무한이므로 소비 대상이 아니다 → 항상 false 취급은 곤란하니
-- 호출부에서 기본 먹이는 consume 하지 않도록 한다(여기선 실제 재고만 다룸).
function DataManager.consumeFood(player: Player, foodId: string): boolean
	local data = cache[player.UserId]
	if not data then
		return false
	end
	local have = data.foods[foodId] or 0
	if have <= 0 then
		return false
	end
	have -= 1
	if have <= 0 then
		data.foods[foodId] = nil
		-- 마지막 한 개를 소진했고 그게 '사용 중' 먹이였다면 기본 먹이로 되돌려
		-- 클라 UI 가 '보유 0개 + 사용 중' 으로 어긋나는 것을 막는다.
		if data.selectedFood == foodId then
			data.selectedFood = GameConfig.DefaultFood
		end
	else
		data.foods[foodId] = have
	end
	DataManager.pushToClient(player)
	return true
end

-- 사용할 먹이 선택. 보유 중이 아니어도 기본 먹이는 선택 가능.
function DataManager.setSelectedFood(player: Player, foodId: string): boolean
	local data = cache[player.UserId]
	if not data or not GameConfig.FoodsById[foodId] then
		return false
	end
	if data.selectedFood ~= foodId then
		data.selectedFood = foodId
		DataManager.pushToClient(player)
	end
	return true
end

-- =====================================================================
-- 악세사리
-- =====================================================================
function DataManager.getAccessories(player: Player): { [string]: boolean }
	local data = cache[player.UserId]
	return (data and data.accessories) or {}
end

function DataManager.hasAccessory(player: Player, accId: string): boolean
	local data = cache[player.UserId]
	return data ~= nil and data.accessories[accId] == true
end

function DataManager.addAccessory(player: Player, accId: string): boolean
	local data = cache[player.UserId]
	if not data or not GameConfig.AccessoriesById[accId] then
		return false
	end
	if data.accessories[accId] then
		return false
	end
	data.accessories[accId] = true
	DataManager.pushToClient(player)
	return true
end

-- 알파카에 악세사리 장착/해제(accId=nil 이면 해제). 성공 여부 반환.
function DataManager.setAlpacaAccessory(player: Player, uid: string, accId: string?): boolean
	local rec = DataManager.getAlpacaByUid(player, uid)
	if not rec then
		return false
	end
	if accId ~= nil and not GameConfig.AccessoriesById[accId] then
		return false
	end
	-- 방어: 보유하지 않은 악세사리는 장착 불가(해제 nil 은 항상 허용).
	if accId ~= nil and not DataManager.hasAccessory(player, accId) then
		return false
	end
	rec.accessory = accId
	DataManager.pushToClient(player)
	return true
end

-- =====================================================================
-- 라이프사이클
-- =====================================================================
function DataManager.init()
	Players.PlayerAdded:Connect(loadData)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadData, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		DataManager.save(player)
		cache[player.UserId] = nil
		loaded[player.UserId] = nil
	end)

	-- 자동 저장 루프
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				DataManager.save(player)
			end
		end
	end)

	-- 서버 종료 시 일괄 저장
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(DataManager.save, player)
		end
		task.wait(3)
	end)
end

return DataManager
