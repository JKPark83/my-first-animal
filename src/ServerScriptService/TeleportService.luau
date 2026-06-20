--!strict
--[[
	TeleportService (서버)
	----------------------
	클라이언트가 RemoteEvent "RequestTeleport" 를 통해 전송한
	텔레포트 요청을 처리합니다.

	지원 대상:
	  - "shop" : 가게 패드 앞 CFrame (FarmBuilder.getShopTeleportCFrame)
	  - "home"  : 플레이어 배정 농장 입구 (FarmBuilder.getPlotInfo(player).spawnCFrame)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Remotes    = require(ReplicatedStorage.Remotes)
local FarmBuilder = require(ServerScriptService.FarmBuilder)

-- 플레이어별 마지막 텔레포트 시각 (디바운스용)
local lastTeleport: { [number]: number } = {}

-- 디바운스 최소 간격 (초)
local DEBOUNCE_SEC = 0.5

local TeleportService = {}

-- target 문자열이 허용된 값인지 확인합니다.
local function isValidTarget(target: unknown): boolean
	return target == "shop" or target == "home" or target == "food" or target == "accessory"
end

-- RequestTeleport 이벤트 핸들러
local function onRequestTeleport(player: Player, target: unknown)
	-- 허용된 대상 문자열만 처리
	if not isValidTarget(target) then
		return
	end

	-- 플레이어별 디바운스 검사
	local now = os.clock()
	local last = lastTeleport[player.UserId]
	if last and (now - last) < DEBOUNCE_SEC then
		return
	end
	lastTeleport[player.UserId] = now

	-- 캐릭터 및 HumanoidRootPart 확인
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not hrp then
		return
	end

	-- 목적지 CFrame 결정
	local cf: CFrame?

	if target == "shop" then
		-- 가게 패드 위(가게를 바라보는 위치)
		cf = FarmBuilder.getShopTeleportCFrame()
	elseif target == "food" then
		-- 먹이 상점 패드 위
		cf = FarmBuilder.getFoodTeleportCFrame()
	elseif target == "accessory" then
		-- 악세사리 가게 패드 위
		cf = FarmBuilder.getAccessoryTeleportCFrame()
	elseif target == "home" then
		-- 플레이어 배정 농장 입구 스폰 위치
		local plot = FarmBuilder.getPlotInfo(player)
		cf = plot and plot.spawnCFrame
	end

	if cf then
		character:PivotTo(cf)
	end
end

-- 외부에서 호출하는 초기화 함수
function TeleportService.init()
	-- RequestTeleport RemoteEvent 에 핸들러 연결
	Remotes.Event("RequestTeleport").OnServerEvent:Connect(onRequestTeleport)

	-- 퇴장한 플레이어의 디바운스 항목 정리 (장기 운영 시 메모리 누수 방지)
	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player.UserId] = nil
	end)
end

return TeleportService
