--!strict
--[[
	Main (서버 부트스트랩)
	---------------------
	실행 순서가 중요합니다:
	  1) 월드 생성(FarmBuilder.build)
	  2) 모든 서비스 init() — 이때 DataManager 훅 등록 + 각 서비스가 자기 Remote 연결
	  3) DataManager.init() 을 "마지막"에 호출 — 그래야 플레이어 로드 시
	     이미 등록된 onLoaded 훅(농장/알파카 스폰)이 동작함.

	이 스크립트는 캐릭터를 농장에 스폰시키고, 가게 패드 진입을 감지합니다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataManager = require(ServerScriptService.DataManager)
local FarmBuilder = require(ServerScriptService.FarmBuilder)
local FarmService = require(ServerScriptService.FarmService)
local AlpacaPreviewBuilder = require(ServerScriptService.AlpacaPreviewBuilder)

-- 리프 서비스 (각자 init 에서 Remote 연결 + 루프 시작)
local AlpacaShopService = require(ServerScriptService.AlpacaShopService)
local CareService = require(ServerScriptService.CareService)
local WoolService = require(ServerScriptService.WoolService)
local CollectionService = require(ServerScriptService.CollectionService)
local AlpacaAI = require(ServerScriptService.AlpacaAI)
local LeaderboardService = require(ServerScriptService.LeaderboardService)
local GamePassService = require(ServerScriptService.GamePassService)
local TeleportService = require(ServerScriptService.TeleportService)

-- =====================================================================
-- 1) 월드
-- =====================================================================
FarmBuilder.build()
AlpacaPreviewBuilder.init() -- 상점 카드용 알파카 미리보기 모델 준비

-- =====================================================================
-- 2) 서비스 init (DataManager 보다 먼저: 훅 등록/Remote 연결)
-- =====================================================================
FarmService.init()
AlpacaShopService.init()
CareService.init()
WoolService.init()
CollectionService.init()
AlpacaAI.init()
LeaderboardService.init()
GamePassService.init()
TeleportService.init()

-- =====================================================================
-- 캐릭터 스폰: 배정된 농장으로 이동
-- =====================================================================
local function placeCharacter(player: Player, character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then
		return
	end
	local plot = FarmBuilder.getPlotInfo(player)
	if plot then
		character:PivotTo(plot.spawnCFrame)
	else
		character:PivotTo(FarmBuilder.getSpawnCFrame())
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(placeCharacter, player, character)
	end)
	if player.Character then
		task.defer(placeCharacter, player, player.Character)
	end
end)

-- =====================================================================
-- 가게 패드 진입 → 상점 열기 신호
-- =====================================================================
local shopPad = FarmBuilder.getShopPad()
if shopPad then
	local lastOpen: { [number]: number } = {}
	shopPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local now = os.clock()
		if lastOpen[player.UserId] and now - lastOpen[player.UserId] < 2 then
			return
		end
		lastOpen[player.UserId] = now
		Remotes.Event("OpenShopRequest"):FireClient(player)
	end)
end

-- =====================================================================
-- 초기 데이터 요청 (클라 부팅 시)
-- =====================================================================
Remotes.Function("GetPlayerData").OnServerInvoke = function(player)
	local waited = 0
	while not DataManager.isLoaded(player) and waited < 10 do
		task.wait(0.2)
		waited += 0.2
	end
	return DataManager.get(player)
end

-- =====================================================================
-- 3) DataManager 마지막 (로드 시작 → onLoaded 훅 발동)
-- =====================================================================
DataManager.init()

print("[AlpacaFarm] 서버 부팅 완료 — 도감 " .. GameConfig.DexTotal .. "종")
