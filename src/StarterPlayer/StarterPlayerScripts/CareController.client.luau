--!strict
--[[
	CareController  (LocalScript — StarterPlayerScripts)
	------------------------------------------------------
	역할:
	  • 화면 하단 중앙에 케어 버튼 3개(먹이주기 / 빗어주기 / 목욕시키기)를 표시합니다.
	  • 매 프레임 캐릭터 근처에 있는 "내 알파카" 모델을 탐지합니다.
	  • 근처 알파카가 있을 때 버튼을 활성화하고, 클릭 시 서버에 케어 요청을 보냅니다.
	  • 서버로부터 CareFeedback 이벤트를 받으면 알파카 머리 위에 플로팅 보상 텍스트를 띄웁니다.
]]

-- ─────────────────────────────────────────────────────────────
-- 서비스 / 모듈
-- ─────────────────────────────────────────────────────────────
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local SoundService   = game:GetService("SoundService")
local Debris         = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes    = require(ReplicatedStorage:WaitForChild("Remotes"))

-- ─────────────────────────────────────────────────────────────
-- 로컬 플레이어 참조
-- ─────────────────────────────────────────────────────────────
local localPlayer = Players.LocalPlayer

-- ─────────────────────────────────────────────────────────────
-- 상태 변수
-- ─────────────────────────────────────────────────────────────
local currentTarget: Model? = nil   -- 현재 근접 타겟 알파카 모델
local currentUid: string?   = nil   -- 타겟의 Uid 속성 값

-- 케어 타입별 AnimationTrack 캐시 (캐릭터 리스폰 시 nil 로 초기화)
local animTrackCache: { [string]: AnimationTrack? } = {}

-- ─────────────────────────────────────────────────────────────
-- UI 구성 — ScreenGui → Frame → 버튼 3개
-- ─────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "CareControllerGui"
screenGui.ResetOnSpawn    = false
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.Parent          = localPlayer:WaitForChild("PlayerGui")

-- 타겟 정보 라벨 (버튼들 바로 위)
local targetLabel = Instance.new("TextLabel")
targetLabel.Name            = "TargetLabel"
targetLabel.Size            = UDim2.new(0, 480, 0, 28)
targetLabel.Position        = UDim2.new(0.5, -240, 1, -130)
targetLabel.BackgroundTransparency = 1
targetLabel.TextColor3      = Color3.fromRGB(255, 255, 255)
targetLabel.TextStrokeTransparency = 0.4
targetLabel.Font            = Enum.Font.GothamBold
targetLabel.TextSize        = 16
targetLabel.Text            = ""
targetLabel.TextXAlignment  = Enum.TextXAlignment.Center
targetLabel.ZIndex          = 10
targetLabel.Parent          = screenGui

-- 버튼을 담을 가로 프레임
local buttonFrame = Instance.new("Frame")
buttonFrame.Name               = "CareButtonFrame"
buttonFrame.Size               = UDim2.new(0, 480, 0, 90)
buttonFrame.Position           = UDim2.new(0.5, -240, 1, -110)
buttonFrame.BackgroundTransparency = 1
buttonFrame.ZIndex             = 10
buttonFrame.Parent             = screenGui

-- 가로 정렬 레이아웃
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection  = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
listLayout.Padding        = UDim.new(0, 12)
listLayout.Parent         = buttonFrame

-- 케어 종류 순서 (왼쪽→오른쪽)
local CARE_ORDER: { "feed" | "brush" | "bath" } = { "feed", "brush", "bath" }

-- 각 버튼 참조를 저장 (careType → TextButton)
local careButtons: { [string]: TextButton } = {}

for _, careType in ipairs(CARE_ORDER) do
	local info = GameConfig.Care.types[careType]

	local btn = Instance.new("TextButton")
	btn.Name             = "CareBtn_" .. careType
	btn.Size             = UDim2.new(0, 144, 0, 80)
	btn.BackgroundColor3 = info.color
	btn.BorderSizePixel  = 0
	btn.Font             = Enum.Font.GothamBold
	btn.TextSize         = 18
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.TextStrokeTransparency = 0.5
	btn.Text             = info.emoji .. "\n" .. info.label
	btn.AutoButtonColor  = false      -- 직접 색을 제어
	btn.ZIndex           = 10
	btn.Parent           = buttonFrame

	-- 둥근 모서리
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = btn

	-- 그림자 느낌 (UIStroke)
	local stroke = Instance.new("UIStroke")
	stroke.Color       = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.6
	stroke.Thickness   = 2
	stroke.Parent      = btn

	careButtons[careType] = btn
end

-- ─────────────────────────────────────────────────────────────
-- 버튼 시각 상태 적용 헬퍼
--   activeZone  : 근처에 타겟이 있는지 (false → 전체 흐림)
--   needReady   : 해당 욕구 값이 careThreshold 이상인지
-- ─────────────────────────────────────────────────────────────
local function applyButtonState(careType: string, activeZone: boolean, needReady: boolean)
	local btn = careButtons[careType]
	if not btn then return end

	if not activeZone then
		-- 비활성: 회색 + 반투명
		btn.BackgroundColor3       = Color3.fromRGB(100, 100, 100)
		btn.BackgroundTransparency = 0.6
		btn.TextTransparency       = 0.5
	elseif needReady then
		-- 케어 가능: 본래 색, 선명
		local info = GameConfig.Care.types[careType]
		btn.BackgroundColor3       = info.color
		btn.BackgroundTransparency = 0
		btn.TextTransparency       = 0
	else
		-- 아직 욕구 부족: 본래 색이지만 살짝 흐리게
		local info = GameConfig.Care.types[careType]
		btn.BackgroundColor3       = info.color
		btn.BackgroundTransparency = 0.45
		btn.TextTransparency       = 0.35
	end
end

-- 초기: 모두 비활성 상태
for _, careType in ipairs(CARE_ORDER) do
	applyButtonState(careType, false, false)
end

-- ─────────────────────────────────────────────────────────────
-- 버튼 클릭 이벤트 연결
-- ─────────────────────────────────────────────────────────────
local requestCareEvent = Remotes.Event("RequestCare")

-- 클라이언트 측 디바운스: 빠른 연타로 RequestCare 가 폭주하는 것을 방지
-- (서버에도 actionDebounce 가 있지만, 요청 자체를 줄여 이중 반응을 막음)
local lastCareClick = 0

for _, careType in ipairs(CARE_ORDER) do
	local btn = careButtons[careType]
	btn.MouseButton1Click:Connect(function()
		if currentUid then
			local now = os.clock()
			if now - lastCareClick < GameConfig.Care.actionDebounce then
				return
			end
			lastCareClick = now
			-- 서버에 케어 요청 전송 (유효성 검사는 서버에서)
			requestCareEvent:FireServer(currentUid, careType)
		end
	end)

	-- 모바일 터치 지원 (TouchTap은 TextButton 이 자동 처리)
	-- AutoButtonColor=false 이므로 눌림 피드백을 직접 구현
	btn.MouseButton1Down:Connect(function()
		btn.BackgroundTransparency = math.min(btn.BackgroundTransparency + 0.15, 0.75)
	end)
	btn.MouseButton1Up:Connect(function()
		-- RenderStepped 루프가 다음 프레임에 자동 복원함
	end)
end

-- ─────────────────────────────────────────────────────────────
-- 근접 탐지 루프 (Heartbeat)
-- ─────────────────────────────────────────────────────────────
local alpacaFarmFolder: Folder? = nil

-- workspace.AlpacaFarm 폴더를 백그라운드에서 대기
task.spawn(function()
	alpacaFarmFolder = workspace:WaitForChild("AlpacaFarm", 60) :: Folder?
end)

RunService.Heartbeat:Connect(function()
	-- 캐릭터 / HumanoidRootPart 체크
	local character = localPlayer.Character
	if not character then
		currentTarget = nil
		currentUid = nil
		targetLabel.Text = ""
		for _, ct in ipairs(CARE_ORDER) do applyButtonState(ct, false, false) end
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or not alpacaFarmFolder then
		currentTarget = nil
		currentUid = nil
		targetLabel.Text = ""
		for _, ct in ipairs(CARE_ORDER) do applyButtonState(ct, false, false) end
		return
	end

	local myPos = hrp.Position
	local myUserId = localPlayer.UserId
	local proximity = GameConfig.Care.proximity

	-- 가장 가까운 내 알파카 탐색
	local bestModel: Model? = nil
	local bestDist  = math.huge

	for _, desc in ipairs(alpacaFarmFolder:GetDescendants()) do
		if desc:IsA("Model") then
			local model = desc :: Model
			-- 내 알파카인지 확인 (AlpacaId 속성 있고 OwnerUserId 일치)
			local alpacaId = model:GetAttribute("AlpacaId")
			local ownerUserId = model:GetAttribute("OwnerUserId")
			if alpacaId and ownerUserId == myUserId then
				local root = model.PrimaryPart
				if root then
					local dist = (root.Position - myPos).Magnitude
					if dist <= proximity and dist < bestDist then
						bestDist  = dist
						bestModel = model
					end
				end
			end
		end
	end

	-- 타겟 갱신
	if bestModel ~= currentTarget then
		currentTarget = bestModel
		currentUid    = bestModel and (bestModel:GetAttribute("Uid") :: string?) or nil
	end

	-- UI 갱신
	if bestModel then
		-- 타겟 정보 라벨 업데이트
		local defId   = bestModel:GetAttribute("AlpacaId") :: string?
		local def     = defId and GameConfig.AlpacasById[defId] or nil
		local alpName = def and def.displayName or (defId or "알파카")
		local hunger  = (bestModel:GetAttribute("Hunger")  :: number?) or 0
		local tangle  = (bestModel:GetAttribute("Tangle")  :: number?) or 0
		local dirt    = (bestModel:GetAttribute("Dirt")    :: number?) or 0

		targetLabel.Text = string.format(
			"%s — 배고픔 %d  털엉킴 %d  더러움 %d",
			alpName, math.floor(hunger), math.floor(tangle), math.floor(dirt)
		)

		-- 각 버튼 상태 (욕구값 >= careThreshold 면 강조)
		local threshold = GameConfig.Care.careThreshold
		local needValues: { [string]: number } = {
			Hunger = hunger,
			Tangle = tangle,
			Dirt   = dirt,
		}

		for _, careType in ipairs(CARE_ORDER) do
			local need      = GameConfig.Care.types[careType].need
			local needVal   = needValues[need] or 0
			local needReady = needVal >= threshold
			applyButtonState(careType, true, needReady)
		end
	else
		-- 타겟 없음
		targetLabel.Text = ""
		for _, careType in ipairs(CARE_ORDER) do
			applyButtonState(careType, false, false)
		end
	end
end)

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 리스폰 시 AnimationTrack 캐시 초기화
-- ─────────────────────────────────────────────────────────────
localPlayer.CharacterAdded:Connect(function()
	-- 이전 캐릭터의 트랙은 더 이상 유효하지 않으므로 전부 제거
	for k in pairs(animTrackCache) do
		animTrackCache[k] = nil
	end
end)

-- ─────────────────────────────────────────────────────────────
-- 케어 성공 피드백 헬퍼들
-- ─────────────────────────────────────────────────────────────

-- [사운드] SoundService 하위에 임시 Sound를 생성해 재생, Debris로 자동 정리
local function playSound(soundId: string)
	if soundId == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId  = soundId
	sound.Volume   = GameConfig.Sounds.volume
	sound.Parent   = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)  -- 4초 후 자동 제거 (대부분 사운드보다 넉넉)
end

-- [바라보기] 로컬 캐릭터의 HumanoidRootPart를 알파카 방향으로 yaw 회전
-- (수직 자세 유지 — X·Z 회전 없이 Y축 yaw 만 적용)
local function faceAlpaca(alpacaModel: Model)
	local character = localPlayer.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local alpacaRoot = alpacaModel.PrimaryPart
	if not alpacaRoot then return end

	local myPos     = hrp.Position
	local targetPos = alpacaRoot.Position
	-- Y 높이를 같게 맞춰 수평 방향 벡터만 추출
	local dir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
	if dir.Magnitude < 0.1 then return end  -- 너무 근접하면 생략 (NaN 방지)

	hrp.CFrame = CFrame.lookAt(myPos, myPos + dir.Unit)
end

-- [애니메이션] careType 에 맞는 제스처 재생, 실패 시 점프 폴백
local function playCareAnim(careType: string)
	local character = localPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then return end

	-- AnimationId 조회 (GameConfig.careAnim 이 careType 별 rbxassetid 반환)
	local animId: string = GameConfig.careAnim(careType)
	if animId == "" then
		-- ID 없음 → 점프 폴백
		humanoid.Jump = true
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		humanoid.Jump = true
		return
	end

	-- 캐시된 트랙 재사용 시도
	local cached: AnimationTrack? = animTrackCache[careType]
	if cached ~= nil then
		local c = cached :: AnimationTrack
		local playOk = pcall(function()
			if not c.IsPlaying then
				c:Play()
			end
		end)
		if playOk then return end
		-- 재생 실패 → 캐시 무효화 후 아래에서 재로드
		animTrackCache[careType] = nil
	end

	-- 새 Animation 인스턴스 생성 후 로드
	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local ok, result = pcall(function(): AnimationTrack
		return animator:LoadAnimation(anim)
	end)

	if ok and result ~= nil then
		local track = result :: AnimationTrack
		animTrackCache[careType] = track
		track:Play()  -- 자동으로 끝나는 이모트 트랙
	else
		-- 로드 실패 → 점프 폴백 (항상 가시적 움직임 보장)
		humanoid.Jump = true
	end
end

-- ─────────────────────────────────────────────────────────────
-- CareFeedback — 플로팅 보상 텍스트
-- ─────────────────────────────────────────────────────────────
local function spawnFloatingText(model: Model, reward: number, careType: string)
	-- 모델의 PrimaryPart 위치 기준으로 BillboardGui 생성
	local root = model.PrimaryPart
	if not root then return end

	local info = GameConfig.Care.types[careType]
	local emoji = info and info.emoji or "✨"

	-- BillboardGui 는 Part에 붙여야 하므로 투명 Part를 임시 생성
	local anchorPart = Instance.new("Part")
	anchorPart.Anchored      = true
	anchorPart.CanCollide    = false
	anchorPart.Transparency  = 1
	anchorPart.Size          = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.CFrame        = root.CFrame + Vector3.new(0, root.Size.Y * 0.5 + 3, 0)
	anchorPart.Parent        = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size            = UDim2.new(0, 160, 0, 50)
	billboard.StudsOffset     = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop     = true
	billboard.LightInfluence  = 0
	billboard.Adornee         = anchorPart
	billboard.Parent          = anchorPart

	local label = Instance.new("TextLabel")
	label.Size                    = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency  = 1
	label.Font                    = Enum.Font.GothamBold
	label.TextSize                = 22
	label.TextColor3              = Color3.fromRGB(255, 240, 80)
	label.TextStrokeTransparency  = 0.2
	label.Text                    = string.format("+$%d %s", reward, emoji)
	label.TextXAlignment          = Enum.TextXAlignment.Center
	label.Parent                  = billboard

	-- 위로 떠오르며 사라지는 트윈
	local riseTween = TweenService:Create(
		anchorPart,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = anchorPart.CFrame + Vector3.new(0, 4, 0) }
	)

	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	riseTween:Play()
	fadeTween:Play()

	-- 트윈 완료 후 정리
	task.delay(1.4, function()
		if anchorPart and anchorPart.Parent then
			anchorPart:Destroy()
		end
	end)
end

-- CareFeedback 이벤트 수신
Remotes.Event("CareFeedback").OnClientEvent:Connect(function(uid: string, careType: string, reward: number)
	-- [1] 케어 효과음은 서버가 알파카 위치에서 재생(AlpacaAI.reactToCare).
	--     → 위치 기반으로 주변 모두(친구 포함)가 듣고, 여기서 중복 재생하지 않음.

	-- [2] workspace.AlpacaFarm 에서 Uid 로 모델 탐색
	local targetModel: Model? = nil
	if alpacaFarmFolder then
		for _, desc in ipairs(alpacaFarmFolder:GetDescendants()) do
			if desc:IsA("Model") then
				local m = desc :: Model
				if m:GetAttribute("Uid") == uid then
					targetModel = m
					break
				end
			end
		end
	end

	if targetModel then
		-- 알파카 방향으로 yaw 회전 (못 찾으면 생략)
		faceAlpaca(targetModel)
		-- 플로팅 보상 텍스트 표시
		spawnFloatingText(targetModel, reward, careType)
	end

	-- [3] 케어 제스처 애니메이션 재생 (모델 유무와 무관하게 항상 실행)
	playCareAnim(careType)
end)
