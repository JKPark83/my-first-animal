--!strict
--[[
	AlpacaPreviewBuilder
	--------------------
	서버 시작 시 각 알파카 종의 "미리보기 모델"을 한 번씩 만들어
	ReplicatedStorage.AlpacaPreviews 폴더에 보관합니다.

	클라이언트(UIController 상점)는 이 모델을 Clone 하여 ViewportFrame 에
	넣어 실제 알파카 외형을 카드 이미지처럼 보여줍니다.
	(별도 이미지 에셋 업로드 없이 코드로 만든 모델을 그대로 미리보기로 사용)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)
local AlpacaSpawner = require(script.Parent.AlpacaSpawner)

local AlpacaPreviewBuilder = {}

local FOLDER_NAME = "AlpacaPreviews"

function AlpacaPreviewBuilder.init()
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage

	for _, def in ipairs(GameConfig.Alpacas) do
		local ok, model = pcall(function()
			return AlpacaSpawner.build({
				defId = def.id,
				uid = "preview",
				ownerUserId = 0,
				hunger = 0,
				tangle = 0,
				dirt = 0,
				happiness = 100,
				wool = 0,
				name = nil,
			})
		end)
		if ok and model then
			-- 미리보기에는 이름표 불필요 → 제거
			local head = model:FindFirstChild("Head")
			if head then
				local tag = head:FindFirstChild("NameTag")
				if tag then
					tag:Destroy()
				end
			end
			model.Name = def.id
			model.Parent = folder
		else
			warn("[AlpacaPreviewBuilder] 미리보기 생성 실패: " .. tostring(def.id))
		end
	end
end

return AlpacaPreviewBuilder
