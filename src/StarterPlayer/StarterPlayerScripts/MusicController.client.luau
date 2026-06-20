--!strict
--[[
	MusicController (LocalScript)
	----------------------------
	배경 음악(BGM) 재생 + 화면 좌하단의 켜기/끄기 토글 버튼.

	- GameConfig.Music.tracks 의 곡을 순서대로 반복 재생합니다.
	  (한 곡이면 무한 루프, 여러 곡이면 끝날 때마다 다음 곡으로)
	- Sound 는 SoundService 에 두어 캐릭터 리스폰과 무관하게 계속 재생됩니다.
	- 토글 상태는 이번 접속 동안만 유지됩니다(영구 저장 아님).

	⚠️ 로블록스 내장 음악 트랙은 없으므로, 친구와 확실히 들으려면
	   GameConfig.Music.tracks 의 id 를 본인 소유/Roblox 제작 오디오로 교체하세요.
]]

local Players          = game:GetService("Players")
local SoundService     = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Music = GameConfig.Music

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── BGM Sound ────────────────────────────────────────────────
local bgm = Instance.new("Sound")
bgm.Name   = "BGM"
bgm.Volume = Music.volume
bgm.Looped = (#Music.tracks <= 1) -- 한 곡이면 루프, 여러 곡이면 Ended 로 넘김
bgm.Parent = SoundService

local trackIndex = 0
local function playNext()
	if #Music.tracks == 0 then
		return
	end
	trackIndex += 1
	if trackIndex > #Music.tracks then
		trackIndex = 1
	end
	bgm.SoundId = Music.tracks[trackIndex]
	bgm:Play()
end

-- 여러 곡일 때만: 곡이 끝나면 다음 곡 재생
bgm.Ended:Connect(function()
	if not bgm.Looped then
		playNext()
	end
end)

local musicOn = Music.enabled

-- ── 토글 버튼 (좌하단) ───────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name          = "MusicControllerGui"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = false
gui.Parent        = playerGui

local btn = Instance.new("TextButton")
btn.Name                   = "MusicToggle"
btn.Size                   = UDim2.new(0, 56, 0, 56)
btn.AnchorPoint            = Vector2.new(0, 1)
btn.Position               = UDim2.new(0, 16, 1, -16)
btn.BackgroundColor3       = Color3.fromRGB(70, 130, 90)
btn.BackgroundTransparency = 0.1
btn.AutoButtonColor        = true
btn.Font                   = Enum.Font.GothamBold
btn.TextSize               = 26
btn.TextColor3             = Color3.fromRGB(255, 255, 255)
btn.Text                   = "🎵"
btn.ZIndex                 = 20
btn.Parent                 = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Color        = Color3.fromRGB(255, 255, 255)
stroke.Thickness    = 2
stroke.Transparency = 0.4
stroke.Parent       = btn

local function applyState()
	if musicOn then
		btn.Text             = "🎵"
		btn.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
		if not bgm.IsPlaying then
			if trackIndex == 0 then
				playNext()
			else
				bgm:Play() -- 일시정지 지점부터 이어재생
			end
		end
	else
		btn.Text             = "🔇"
		btn.BackgroundColor3 = Color3.fromRGB(120, 70, 70)
		bgm:Pause()
	end
end

btn.Activated:Connect(function()
	musicOn = not musicOn
	applyState()
end)

-- 시작 상태 적용
applyState()

print("[MusicController] BGM 컨트롤러 초기화 완료 🎵")
