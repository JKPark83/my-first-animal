--!strict
--[[
	FarmService
	-----------
	DataManager · FarmBuilder · AlpacaSpawner 를 잇는 글루 계층.
	- 접속 시 농장 배정 + 저장된 알파카 무리 스폰 (DataManager.onLoaded)
	- 저장 직전 모델 상태(욕구/양털) → 데이터 동기화 (DataManager.onBeforeSave)
	- 알파카 모델 조회/생성/삭제 API 제공 (Shop/Care/Wool/AI 서비스가 사용)

	슬롯 점유: 각 모델에 "SlotIndex" 속성을 부여해 빈 슬롯을 찾습니다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local DataManager = require(script.Parent.DataManager)
local FarmBuilder = require(script.Parent.FarmBuilder)
local AlpacaSpawner = require(script.Parent.AlpacaSpawner)

local FarmService = {}

-- =====================================================================
-- 조회 헬퍼
-- =====================================================================
function FarmService.getPlotInfo(player: Player): FarmBuilder.PlotInfo?
	return FarmBuilder.getPlotInfo(player)
end

function FarmService.getAlpacaModels(player: Player): { Model }
	local plot = FarmBuilder.getPlotInfo(player)
	if not plot then
		return {}
	end
	local result: { Model } = {}
	for _, child in ipairs(plot.alpacasFolder:GetChildren()) do
		if child:IsA("Model") then
			result[#result + 1] = child
		end
	end
	return result
end

function FarmService.getModelByUid(player: Player, uid: string): Model?
	local plot = FarmBuilder.getPlotInfo(player)
	if not plot then
		return nil
	end
	for _, child in ipairs(plot.alpacasFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Uid") == uid then
			return child
		end
	end
	return nil
end

-- 모델 소유 플레이어
function FarmService.ownerOf(model: Model): Player?
	local id = model:GetAttribute("OwnerUserId")
	if type(id) == "number" then
		return Players:GetPlayerByUserId(id)
	end
	return nil
end

-- 빈 슬롯 인덱스 + CFrame 반환
local function findFreeSlot(plot: FarmBuilder.PlotInfo): (number?, CFrame?)
	local used: { [number]: boolean } = {}
	for _, child in ipairs(plot.alpacasFolder:GetChildren()) do
		if child:IsA("Model") then
			local idx = child:GetAttribute("SlotIndex")
			if type(idx) == "number" then
				used[idx] = true
			end
		end
	end
	for i = 1, #plot.slotCFrames do
		if not used[i] then
			return i, plot.slotCFrames[i]
		end
	end
	return nil, nil
end

-- =====================================================================
-- 스폰 / 제거
-- =====================================================================
-- 레코드 한 마리를 빈 슬롯에 스폰. 성공 시 Model, 실패 시 nil.
function FarmService.spawnAlpaca(player: Player, record: DataManager.AlpacaRecord): Model?
	local plot = FarmBuilder.getPlotInfo(player)
	if not plot then
		return nil
	end
	local slotIndex, slotCF = findFreeSlot(plot)
	if not slotIndex or not slotCF then
		return nil
	end

	local model = AlpacaSpawner.build({
		defId = record.defId,
		uid = record.uid,
		ownerUserId = player.UserId,
		hunger = record.hunger,
		tangle = record.tangle,
		dirt = record.dirt,
		happiness = record.happiness,
		wool = record.wool,
		name = record.name,
		accessory = record.accessory,
	})
	model:SetAttribute("SlotIndex", slotIndex)
	model:SetAttribute("HomeX", slotCF.Position.X)
	model:SetAttribute("HomeZ", slotCF.Position.Z)
	-- 굶주림 사망 타이머 기준: 스폰/접속 시점을 "마지막 먹인 시각"으로 초기화한다.
	-- (오프라인 방치로는 죽지 않게 하기 위함 — 접속 중에만 카운트)
	model:SetAttribute("Fed", os.time())
	model.Parent = plot.alpacasFolder
	AlpacaSpawner.placeOnGround(model, slotCF)
	return model
end

function FarmService.removeAlpacaModel(player: Player, uid: string)
	local model = FarmService.getModelByUid(player, uid)
	if model then
		model:Destroy()
	end
end

-- =====================================================================
-- 라이프사이클 훅
-- =====================================================================
local function onLoaded(player: Player)
	-- 농장 배정
	local idx = FarmBuilder.assignPlot(player)
	if not idx then
		warn("[FarmService] 빈 농장이 없습니다: " .. player.Name)
		return
	end

	-- 저장된 알파카 스폰
	local data = DataManager.get(player)
	if data then
		for _, record in ipairs(data.alpacas) do
			FarmService.spawnAlpaca(player, record)
		end
	end

	-- 이미 캐릭터가 있으면 농장으로 이동
	local plot = FarmBuilder.getPlotInfo(player)
	if plot and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			(player.Character :: Model):PivotTo(plot.spawnCFrame)
		end
	end
end

local function onBeforeSave(player: Player)
	-- 모델의 현재 상태를 데이터로 되돌림
	for _, model in ipairs(FarmService.getAlpacaModels(player)) do
		local uid = model:GetAttribute("Uid")
		if type(uid) == "string" then
			DataManager.syncAlpacaState(player, uid, {
				hunger = (model:GetAttribute("Hunger") :: number) or 0,
				tangle = (model:GetAttribute("Tangle") :: number) or 0,
				dirt = (model:GetAttribute("Dirt") :: number) or 0,
				happiness = (model:GetAttribute("Happiness") :: number) or 100,
				wool = (model:GetAttribute("Wool") :: number) or 0,
			})
		end
	end
end

function FarmService.init()
	DataManager.onLoaded(onLoaded)
	DataManager.onBeforeSave(onBeforeSave)

	-- 플롯/알파카 모델 반납은 "최종 저장 이후"에 일어나야 한다.
	-- (직접 PlayerRemoving 에 붙이면 DataManager 보다 먼저 등록돼 모델이 저장 전에
	--  파괴되고, onBeforeSave 의 모델→데이터 동기화가 빈 목록으로 스킵된다.)
	DataManager.onCleanup(function(player)
		FarmBuilder.releasePlot(player)
	end)
end

return FarmService
