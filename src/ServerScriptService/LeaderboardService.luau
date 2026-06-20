--!strict
--[[
	LeaderboardService
	-------------------
	글로벌 총자산(netWorth) 순위를 관리합니다.

	주요 역할:
	- OrderedDataStore("AlpacaWorth_v1") 에 플레이어별 순자산을 주기적으로 기록
	- 일정 간격으로 상위 N명 순위를 읽어 캐시하고 전광판 + 클라이언트에 배포
	- Studio 환경이나 권한 없음 폴백: 현재 접속자 기준 인메모리 순위로 대체
	- RemoteFunction "GetLeaderboard" 를 통해 클라이언트가 순위 + 본인 순자산 조회 가능

	구독/배포 흐름:
	  제출 루프(submitInterval 초마다)  →  ODS 에 각 플레이어 worth 기록
	  갱신 루프(cacheSeconds 초마다)    →  ODS 조회 → cachedEntries 갱신
	                                    →  FarmBuilder.updateLeaderboard 전광판 갱신
	                                    →  "LeaderboardUpdated" 전체 클라이언트 브로드캐스트
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes   = require(ReplicatedStorage.Remotes)
local DataManager = require(script.Parent.DataManager)
local FarmBuilder = require(script.Parent.FarmBuilder)

local LeaderboardService = {}

-- =====================================================================
-- 내부 상태
-- =====================================================================
-- OrderedDataStore 인스턴스 (pcall 실패 시 nil → 폴백 모드)
local ods: OrderedDataStore? = nil

-- 마지막으로 만든 순위 캐시
local cachedEntries: { { rank: number, name: string, worth: number } } = {}

-- userId → 표시 이름 캐시 (Players:GetNameFromUserIdAsync 결과 재활용)
local nameCache: { [number]: string } = {}

-- =====================================================================
-- 헬퍼: userId 로 표시 이름 얻기 (캐시 우선)
-- =====================================================================
local function getPlayerName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	-- 이름 조회 시도
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name: string = (ok and type(result) == "string") and result or ("Player" .. tostring(userId))
	nameCache[userId] = name
	return name
end

-- =====================================================================
-- 헬퍼: 현재 접속자 기준 인메모리 폴백 순위 생성
-- =====================================================================
local function buildFallbackEntries(): { { rank: number, name: string, worth: number } }
	local topCount = GameConfig.Leaderboard.topCount

	-- 접속자 목록 수집
	local list: { { userId: number, name: string, worth: number } } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if DataManager.isLoaded(player) then
			list[#list + 1] = {
				userId = player.UserId,
				name   = player.Name,
				worth  = DataManager.netWorth(player),
			}
		end
	end

	-- 순자산 내림차순 정렬
	table.sort(list, function(a, b)
		return a.worth > b.worth
	end)

	-- 상위 topCount 만 추출
	local entries: { { rank: number, name: string, worth: number } } = {}
	for i = 1, math.min(#list, topCount) do
		entries[i] = { rank = i, name = list[i].name, worth = list[i].worth }
	end
	return entries
end

-- =====================================================================
-- 헬퍼: ODS 에서 순위 읽어오기
-- 반환: entries 배열 또는 실패 시 nil
-- =====================================================================
local function fetchOdsEntries(): { { rank: number, name: string, worth: number } }?
	if not ods then
		return nil
	end
	local topCount = GameConfig.Leaderboard.topCount

	-- GetSortedAsync: 내림차순(false), 상위 topCount
	local ok, pageOrErr = pcall(function()
		return (ods :: OrderedDataStore):GetSortedAsync(false, topCount)
	end)
	if not ok then
		warn("[LeaderboardService] ODS 조회 실패:", pageOrErr)
		return nil
	end

	local page = pageOrErr :: DataStorePages
	local rawList: { { key: string, value: number } }
	local pageOk, pageErr = pcall(function()
		rawList = page:GetCurrentPage() :: { { key: string, value: number } }
	end)
	if not pageOk then
		warn("[LeaderboardService] 페이지 읽기 실패:", pageErr)
		return nil
	end

	local entries: { { rank: number, name: string, worth: number } } = {}
	for i, item in ipairs(rawList) do
		-- key 형식: "u_<userId>"
		local key   = item.key   :: string
		local worth = item.value :: number
		local userIdStr = key:match("^u_(%d+)$")
		if userIdStr then
			local userId = tonumber(userIdStr) :: number
			local name   = getPlayerName(userId)
			entries[i]   = { rank = i, name = name, worth = worth }
		end
	end
	return entries
end

-- =====================================================================
-- 순위 갱신: 캐시 + 전광판 + 클라이언트 브로드캐스트
-- =====================================================================
local function refreshLeaderboard()
	local entries = fetchOdsEntries()

	-- ODS 실패 또는 폴백 모드면 현재 접속자로 대체
	if not entries or #entries == 0 then
		entries = buildFallbackEntries()
	end

	cachedEntries = entries

	-- 전광판(FarmBuilder 빌보드) 갱신
	FarmBuilder.updateLeaderboard(cachedEntries)

	-- 모든 클라이언트에 순위 배포
	Remotes.Event("LeaderboardUpdated"):FireAllClients(cachedEntries)
end

-- =====================================================================
-- init: 루프 시작, RemoteFunction 등록
-- =====================================================================
function LeaderboardService.init()
	-- ── ODS 초기화 ──────────────────────────────────────────────────
	local odsOk, odsResult = pcall(function()
		return DataStoreService:GetOrderedDataStore("AlpacaWorth_v1")
	end)
	if odsOk then
		ods = odsResult :: OrderedDataStore
	else
		warn("[LeaderboardService] OrderedDataStore 초기화 실패 (폴백 모드):", odsResult)
		ods = nil
	end

	-- ── 제출 루프: 매 submitInterval 초마다 순자산 기록 ─────────────
	task.spawn(function()
		while true do
			task.wait(GameConfig.Leaderboard.submitInterval)

			if ods then
				for _, player in ipairs(Players:GetPlayers()) do
					if DataManager.isLoaded(player) then
						local worth = math.max(0, DataManager.netWorth(player))
						local key   = "u_" .. tostring(player.UserId)
						-- ODS SetAsync 실패해도 다음 사이클에 재시도
						local setOk, setErr = pcall(function()
							(ods :: OrderedDataStore):SetAsync(key, worth)
						end)
						if not setOk then
							warn("[LeaderboardService] 순자산 저장 실패 (", player.Name, "):", setErr)
						end
					end
				end
			end
		end
	end)

	-- ── 갱신 루프: 시작 시 1회 즉시 실행 후 cacheSeconds 마다 반복 ──
	task.spawn(function()
		-- 시작 직후 1회
		refreshLeaderboard()

		while true do
			task.wait(GameConfig.Leaderboard.cacheSeconds)
			refreshLeaderboard()
		end
	end)

	-- ── RemoteFunction: 클라이언트가 순위 + 본인 순자산 조회 ─────────
	Remotes.Function("GetLeaderboard").OnServerInvoke = function(player: Player)
		return {
			entries = cachedEntries or {},
			myWorth = DataManager.netWorth(player),
		}
	end
end

return LeaderboardService
