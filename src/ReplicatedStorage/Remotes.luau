--!strict
--[[
	Remotes
	--------
	클라이언트 ↔ 서버 통신에 쓰는 RemoteEvent / RemoteFunction을
	한곳에서 정의하고 가져옵니다.

	서버에서 먼저 require 되면 인스턴스를 생성하고,
	클라이언트에서 require 되면 생성될 때까지 기다렸다가 가져옵니다.

	사용 예)
		local Remotes = require(ReplicatedStorage.Remotes)
		Remotes.Event("RequestBuyAlpaca"):FireServer(defId)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GameRemotes"

-- 정의할 원격 통신 목록
local EVENT_NAMES = {
	-- 클라 → 서버
	"RequestBuyAlpaca", -- 알파카 구매 요청 (defId)
	"RequestNameAlpaca", -- 알파카 별명 설정 (uid, name)
	"RequestExpandSlot", -- 농장 슬롯 확장 요청
	"RequestCare", -- 케어 요청 (uid, careType: "feed"|"brush"|"bath")
	"RequestCollectWool", -- 양털 수집 요청 (uid 또는 nil=전체)
	"RequestBuyGamePass", -- 로벅스 게임패스 구매 요청 (passKey)
	"RequestTeleport", -- 빠른 이동 요청 (target: "shop"|"home"|"food"|"accessory")
	"RequestBuyFood", -- 먹이 구매 요청 (foodId)
	"RequestSelectFood", -- 사용할 먹이 선택 요청 (foodId)
	"RequestBuyAccessory", -- 악세사리 구매 요청 (accId)
	"RequestEquipAccessory", -- 악세사리 착용/해제 요청 (uid, accId 또는 ""=벗기기)

	-- 서버 → 클라
	"PlayerDataUpdated", -- 플레이어 데이터(머니/슬롯/도감/보유알파카/부스트/먹이/악세사리) 갱신
	"CareFeedback", -- 케어 성공 피드백 (uid, careType, reward) — 화면 플로팅 텍스트용
	"WoolCollected", -- 양털 수집 결과 (amount) — 피드백
	"LeaderboardUpdated", -- 글로벌 총자산 순위 갱신
	"OpenShopRequest", -- 알파카 가게 패드를 밟으면 클라에 상점 열기 신호
	"OpenFoodShop", -- 먹이 상점 패드를 밟으면 클라에 먹이 상점 열기 신호
	"OpenAccessoryShop", -- 악세사리 가게 패드를 밟으면 클라에 악세사리 가게 열기 신호
	"PromptNameAlpaca", -- 구매 직후 이름짓기 모달 요청 (uid, defId, displayName)
	"Notify", -- 일반 알림 메시지
}

local FUNCTION_NAMES = {
	"GetPlayerData", -- 최초 접속 시 데이터 일괄 요청
	"GetLeaderboard", -- 글로벌 순위표 + 개인 총자산 요청
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
end

local function getOrCreate(folder: Folder, name: string, className: string): Instance
	if RunService:IsServer() then
		local inst = folder:FindFirstChild(name)
		if not inst then
			inst = Instance.new(className)
			inst.Name = name
			inst.Parent = folder
		end
		return inst
	else
		return folder:WaitForChild(name)
	end
end

-- 서버에서 require 시 모든 원격 객체를 미리 생성
local function ensureAll()
	local folder = getFolder()
	if RunService:IsServer() then
		for _, name in ipairs(EVENT_NAMES) do
			getOrCreate(folder, name, "RemoteEvent")
		end
		for _, name in ipairs(FUNCTION_NAMES) do
			getOrCreate(folder, name, "RemoteFunction")
		end
	end
end

ensureAll()

-- 이름으로 RemoteEvent 가져오기
function Remotes.Event(name: string): RemoteEvent
	local folder = getFolder()
	return getOrCreate(folder, name, "RemoteEvent") :: RemoteEvent
end

-- 이름으로 RemoteFunction 가져오기
function Remotes.Function(name: string): RemoteFunction
	local folder = getFolder()
	return getOrCreate(folder, name, "RemoteFunction") :: RemoteFunction
end

return Remotes
