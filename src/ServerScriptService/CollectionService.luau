--!strict
--[[
	CollectionService
	-----------------
	도감(Pokedex 스타일) 등록 및 완성 보상을 담당하는 서버 모듈.

	- AlpacaShopService 등 외부 모듈이 CollectionService.register(player, defId) 를 호출.
	- GameConfig.AlpacasById[defId] 를 조회하여 도감 등록 여부(countInDex)를 확인.
	- 새 알파카 등록 시 플레이어에게 알림 전송.
	- 도감 완성(전체 종 등록) 시 세션 내 1회에 한해 큰 보상(머니 1,000,000) 지급.
	- completedReward 테이블로 세션 중복 보상을 방지하며, PlayerRemoving 시 정리.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes   = require(ReplicatedStorage.Remotes)
local DataManager = require(script.Parent.DataManager)

local CollectionService = {}

-- 세션 내 도감 완성 보상 지급 여부 추적 (userId -> true)
local completedReward: { [number]: boolean } = {}

-- 도감에 알파카를 등록하고, 필요 시 완성 보상을 지급한다.
function CollectionService.register(player: Player, defId: string)
	-- 알파카 정의 조회; 없으면 안전하게 종료
	local def = GameConfig.AlpacasById[defId]
	if not def then
		return
	end

	-- 도감 등록 대상이 아닌 알파카는 건너뜀
	if not def.countInDex then
		return
	end

	-- DataManager 에 실제 등록 시도 (이미 등록된 경우 false 반환)
	local isNew = DataManager.markDex(player, defId)

	if isNew then
		local count = DataManager.getDexCount(player)
		local total = GameConfig.DexTotal

		-- 새 알파카 등록 알림
		Remotes.Event("Notify"):FireClient(
			player,
			"📖 도감 새 알파카 등록: " .. def.displayName
				.. " (" .. tostring(count) .. "/" .. tostring(total) .. ")"
		)

		-- 도감 완성 체크: 전체 종 수를 채웠고 이번 세션에 아직 보상을 받지 않았으면 지급
		if count >= total then
			local userId = player.UserId
			if not completedReward[userId] then
				completedReward[userId] = true
				DataManager.addMoney(player, 1000000)
				Remotes.Event("Notify"):FireClient(
					player,
					"🏆 도감 완성! 보상 1,000,000 지급!"
				)
			end
		end
	end
end

-- 초기화: 현재 연결할 Remote 는 없지만, PlayerRemoving 훅으로 세션 테이블을 정리한다.
function CollectionService.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		completedReward[player.UserId] = nil
	end)
end

return CollectionService
