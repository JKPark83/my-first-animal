--!strict
--[[
    AlpacaAI
    --------
    알파카 모델들이 자신의 농장 구역(plot.bounds) 안을
    자연스럽게 어슬렁거리며 배회하도록 제어하는 서버 AI 모듈.

    동작 방식:
    - 단일 RunService.Heartbeat 루프에서 모든 플레이어의 알파카를 일괄 처리.
      (모델마다 별도 코루틴 없음 → GC/스케줄러 부담 최소화)
    - 각 모델에 { target, pauseUntil, speed, yaw, phase, … } 상태를 유지.
    - GameConfig.Wander 설정값으로 가/감속, 부드러운 회전, 걷기 들썩임 구현.
    - 목적지 도달 시 bounds 내 새 임의 목적지를 고르고,
      pauseChance 확률로 pauseMin~pauseMax 초 휴식(풀 뜯기).
    - AlpacaSpawner.placeOnGround 로 배치 → 모델 속성 자동 복제.
    - 주기적으로 부모가 사라진 모델의 state 를 정리(메모리 누수 방지).
    - AlpacaAI.reactToCare(model, careType, byPlayer): 케어 깡총 반응 API.
]]

local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage.GameConfig)
local FarmService   = require(script.Parent.FarmService)
local AlpacaSpawner = require(script.Parent.AlpacaSpawner)

-- GameConfig 하위 테이블을 모듈 상단에서 캐시 (Heartbeat 성능 최적화)
local Wander       = GameConfig.Wander        -- 배회 파라미터
local CareReaction = GameConfig.CareReaction  -- 케어 반응 파라미터

local AlpacaAI = {}

-- =====================================================================
-- 상수
-- =====================================================================
local CLEANUP_INTERVAL = 5.0      -- state 정리 주기 (초)
local TWO_PI           = math.pi * 2

-- =====================================================================
-- 로컬 타입 정의
-- =====================================================================
type Bounds = {
    minX: number,
    maxX: number,
    minZ: number,
    maxZ: number,
}

-- 다리 보행용: 한 발(다리+발굽)의 정보
--   hipLocal     : 회전 기준점(엉덩이) — 모델 로컬 좌표
--   phaseOffset  : 보행 위상 오프셋 (대각선 다리쌍이 같은 위상 → trot 걸음)
--   parts        : 이 발에 속한 파트들과 각자의 '쉬는 자세' 로컬 CFrame
type Foot = {
    hipLocal    : Vector3,
    phaseOffset : number,
    parts       : { { part: BasePart, restLocalCF: CFrame } },
}

-- 모델별 AI 상태
type AIState = {
    target     : Vector3, -- 현재 목적지 (groundY 기준 XZ 평면)
    pauseUntil : number,  -- 정지 끝나는 시각 (os.clock)
    speed      : number,  -- 현재 이동 속도 (studs/s, 가/감속)
    yaw        : number,  -- 현재 모델 yaw (라디안, Y 축 회전)
    phase      : number,  -- 걸음(다리 스윙/bob) 위상 누적값
    legs       : { Foot },-- 다리 4발 정보 (보행 애니메이션용)
    -- 케어 반응 상태
    reactUntil : number,  -- 반응 끝나는 시각 (0 이면 반응 없음)
    reactPhase : number,  -- 깡총 hop 위상 누적값
    faceYaw    : number,  -- 반응 중 바라볼 yaw (reactUntil > 0 일 때만 유효)
}

-- =====================================================================
-- 내부 state 테이블 (Model → AIState)
-- =====================================================================
local state: { [Model]: AIState } = {}
local lastCleanup = 0

-- =====================================================================
-- 헬퍼: 경계 안 임의의 Vector3 반환 (Y = groundY)
-- =====================================================================
local function randomInBounds(bounds: Bounds, groundY: number): Vector3
    local x = bounds.minX + math.random() * (bounds.maxX - bounds.minX)
    local z = bounds.minZ + math.random() * (bounds.maxZ - bounds.minZ)
    return Vector3.new(x, groundY, z)
end

-- =====================================================================
-- 헬퍼: 수평 거리 (Y 성분 무시)
-- =====================================================================
local function horizDist(a: Vector3, b: Vector3): number
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- =====================================================================
-- 헬퍼: yaw 최단각 보간 (스냅 없이 부드럽게)
--   CFrame.Angles(0, yaw, 0) 기준: LookVector = (-sin(yaw), 0, -cos(yaw))
--   rate 는 초당 보간 비율 (turnRate). math.min(rate*dt, 1) 로 오버슛 방지.
-- =====================================================================
local function lerpYaw(current: number, target: number, rate: number, dt: number): number
    -- 각도 차이를 -π ~ +π 범위로 정규화하여 최단 경로 선택
    local diff = (target - current) % TWO_PI
    if diff > math.pi then diff = diff - TWO_PI end
    return current + diff * math.min(rate * dt, 1.0)
end

-- =====================================================================
-- 헬퍼: from → to 방향을 향하는 yaw 각도 반환
--   CFrame.Angles(0, yaw, 0) 기준 LookVector = (-sin(yaw), 0, -cos(yaw)) 이므로
--   방향 벡터 (dx, dz) 에서 yaw = atan2(-dx, -dz)
-- =====================================================================
local function yawToward(from: Vector3, to: Vector3): number
    local dx = to.X - from.X
    local dz = to.Z - from.Z
    return math.atan2(-dx, -dz)
end

-- =====================================================================
-- 헬퍼: 모델의 다리("Leg")·발굽("Hoof") 파트를 4발로 묶어 정보 수집
--   각 파트의 '쉬는 자세'를 root 기준 로컬 CFrame 으로 저장해 두고,
--   매 프레임 엉덩이(hip)를 축으로 앞뒤로 회전시켜 보행을 만든다.
--   X·Z 부호로 발 위치를 구분(L/R, F/B), 대각선 쌍은 같은 위상.
-- =====================================================================
local function collectLegs(model: Model, root: BasePart): { Foot }
    local rootCF = root.CFrame
    local feet: { [string]: Foot } = {}

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and (child.Name == "Leg" or child.Name == "Hoof") then
            local part = child :: BasePart
            local localCF = rootCF:ToObjectSpace(part.CFrame)
            local pos = localCF.Position
            local key = ((pos.X >= 0) and "R" or "L") .. ((pos.Z >= 0) and "B" or "F")

            local foot = feet[key]
            if not foot then
                foot = {
                    -- Leg 파트를 만나면 정확한 hip(다리 윗면)로 갱신됨
                    hipLocal    = Vector3.new(pos.X, pos.Y, pos.Z),
                    phaseOffset = ((pos.X * pos.Z) > 0) and 0 or math.pi,
                    parts       = {},
                }
                feet[key] = foot
            end

            table.insert(foot.parts, { part = part, restLocalCF = localCF })

            -- 다리 본체면 엉덩이 위치 = 다리 중심 + 절반 높이(윗면)
            if part.Name == "Leg" then
                foot.hipLocal = Vector3.new(pos.X, pos.Y + part.Size.Y * 0.5, pos.Z)
            end
        end
    end

    local list: { Foot } = {}
    for _, foot in feet do
        table.insert(list, foot)
    end
    return list
end

-- =====================================================================
-- 헬퍼: 다리 보행 포즈 적용
--   amp   : 스윙 진폭(라디안). 0 이면 쉬는 자세(정지).
--   phase : 걸음 위상
--   각 발을 hipLocal 축으로 swing 만큼 회전(엉덩이 피벗) → 다리+발굽이 함께 움직임.
-- =====================================================================
local function applyLegPose(legs: { Foot }, rootCF: CFrame, amp: number, phase: number)
    for _, foot in ipairs(legs) do
        local swing   = amp * math.sin(phase + foot.phaseOffset)
        local pivotCF = CFrame.new(foot.hipLocal)
        -- 엉덩이를 축으로 X축 회전(앞뒤 스윙): pivot * R * pivot⁻¹
        local rot = pivotCF * CFrame.Angles(swing, 0, 0) * pivotCF:Inverse()
        for _, entry in ipairs(foot.parts) do
            entry.part.CFrame = rootCF * (rot * entry.restLocalCF)
        end
    end
end

-- =====================================================================
-- 헬퍼: 부모가 없어진(사라진) 모델의 state 항목 제거
-- =====================================================================
local function cleanupState()
    local toRemove: { Model } = {}
    for model in state do
        if model.Parent == nil then
            toRemove[#toRemove + 1] = model
        end
    end
    for _, model in ipairs(toRemove) do
        state[model] = nil
    end
end

-- =====================================================================
-- Heartbeat 콜백: 매 프레임 실행
-- =====================================================================
local function onHeartbeat(dt: number)
    local now = os.clock()

    -- 주기적 state 정리 (메모리 누수 방지)
    if now - lastCleanup >= CLEANUP_INTERVAL then
        lastCleanup = now
        cleanupState()
    end

    -- 모든 접속 플레이어 순회
    for _, player in ipairs(Players:GetPlayers()) do
        local plot = FarmService.getPlotInfo(player)
        if not plot then continue end

        local bounds  = plot.bounds :: Bounds
        local groundY = plot.origin.Y
        local models  = FarmService.getAlpacaModels(player)

        for _, model in ipairs(models) do
            -- PrimaryPart 없으면 건너뜀
            local primary = model.PrimaryPart
            if not primary then continue end

            -- ── state 초기화 (처음 보는 모델) ──────────────────────
            if not state[model] then
                local pivot   = model:GetPivot()
                local pos     = pivot.Position
                local lv      = pivot.LookVector
                -- LookVector = (-sin(yaw), 0, -cos(yaw)) 에서 yaw 역산:
                --   sin(yaw) = -lv.X, cos(yaw) = -lv.Z
                --   → yaw = atan2(-lv.X, -lv.Z)
                local initYaw = math.atan2(-lv.X, -lv.Z)
                state[model] = {
                    target     = Vector3.new(pos.X, groundY, pos.Z),
                    pauseUntil = 0,
                    speed      = 0,
                    yaw        = initYaw,
                    phase      = 0,
                    legs       = collectLegs(model, primary),
                    reactUntil = 0,
                    reactPhase = 0,
                    faceYaw    = initYaw,
                }
            end

            local s = state[model]

            -- ─────────────────────────────────────────────────────────
            -- [케어 반응 모드] reactUntil 이 남아 있는 동안 깡총 수행
            -- ─────────────────────────────────────────────────────────
            if now < s.reactUntil then
                -- hop 위상 진행: duration 초 동안 hopCount 개 봉우리
                --   봉우리 1개 = |sin| 반주기(π) → 총 hopCount * π 진행
                local hopRate = (CareReaction.hopCount * math.pi) / CareReaction.duration
                s.reactPhase  = s.reactPhase + hopRate * dt

                -- 수직 깡총 오프셋 (|sin| 로 부드러운 봉우리)
                local hopY = CareReaction.hopHeight * math.abs(math.sin(s.reactPhase))

                -- facePlayer: 케어한 플레이어 방향으로 부드럽게 yaw 보간
                if CareReaction.facePlayer then
                    s.yaw = lerpYaw(s.yaw, s.faceYaw, Wander.turnRate * 3, dt)
                end

                -- 제자리 깡총: XZ 이동 없이 Y 만 변화
                local pivotPos = model:GetPivot().Position
                local groundCF = CFrame.new(
                    Vector3.new(pivotPos.X, groundY + hopY, pivotPos.Z)
                ) * CFrame.Angles(0, s.yaw, 0)

                AlpacaSpawner.placeOnGround(model, groundCF)
                applyLegPose(s.legs, primary.CFrame, 0, s.phase) -- 깡총 중 다리는 쉬는 자세
                continue
            end

            -- 반응이 막 끝났으면 reactUntil 초기화 → 다음 프레임부터 배회 재개
            if s.reactUntil > 0 then
                s.reactUntil = 0
                s.reactPhase = 0
            end

            -- ── 정지 중이면 현재 위치 유지 ──────────────────────────
            if now < s.pauseUntil then
                applyLegPose(s.legs, primary.CFrame, 0, s.phase) -- 풀 뜯으며 정지: 다리 쉬는 자세
                continue
            end

            -- ── 현재 ground 위치 (X/Z 는 pivot, Y 는 바닥 윗면) ────
            local pivotPos  = model:GetPivot().Position
            local curGround = Vector3.new(pivotPos.X, groundY, pivotPos.Z)

            -- ── 목적지 도달 확인 → 감속 및 새 목적지 선정 ───────────
            local distToTarget = horizDist(curGround, s.target)
            if distToTarget < Wander.arriveDist then
                -- 목표 속도 0 으로: accel 속도로 부드럽게 감속
                s.speed = math.max(s.speed - Wander.accel * dt, 0)

                -- 완전히 멈추면 새 목적지 선정
                if s.speed < 0.01 then
                    s.speed  = 0
                    s.target = randomInBounds(bounds, groundY)

                    -- pauseChance 확률로 풀 뜯기 휴식
                    if math.random() < Wander.pauseChance then
                        local dur = Wander.pauseMin
                            + math.random() * (Wander.pauseMax - Wander.pauseMin)
                        s.pauseUntil = now + dur
                    end
                end

                -- 감속 중: 위치 유지(bob 없음). 다리는 남은 속도에 비례해 점차 멈춤.
                local groundCF = CFrame.new(curGround) * CFrame.Angles(0, s.yaw, 0)
                AlpacaSpawner.placeOnGround(model, groundCF)
                local decelRatio = s.speed / Wander.moveSpeed
                s.phase = s.phase + Wander.bobSpeed * dt * decelRatio
                applyLegPose(s.legs, primary.CFrame, Wander.legSwing * decelRatio, s.phase)
                continue
            end

            -- ── 목표 속도(moveSpeed)로 accel 기반 가속 ──────────────
            s.speed = math.min(s.speed + Wander.accel * dt, Wander.moveSpeed)

            -- ── 진행 방향 yaw 계산 및 최단각 보간 (스냅 금지) ────────
            local dir    = s.target - curGround  -- s.target.Y = groundY 이므로 수평
            local dirLen = dir.Magnitude

            if dirLen < 0.001 then continue end

            -- atan2(-dx, -dz): LookVector(-sin(yaw), 0, -cos(yaw)) 기준
            local targetYaw = math.atan2(-dir.X, -dir.Z)
            s.yaw = lerpYaw(s.yaw, targetYaw, Wander.turnRate, dt)

            -- ── 이동 계산 ───────────────────────────────────────────
            local step   = math.min(s.speed * dt, dirLen)
            local newPos = curGround + (dir / dirLen) * step

            -- plot.bounds 밖으로 나가지 않도록 클램프 (방어 처리)
            newPos = Vector3.new(
                math.clamp(newPos.X, bounds.minX, bounds.maxX),
                groundY,
                math.clamp(newPos.Z, bounds.minZ, bounds.maxZ)
            )

            -- ── 걸음 위상 진행(속도 비례) ───────────────────────────
            local speedRatio = s.speed / Wander.moveSpeed
            s.phase = s.phase + Wander.bobSpeed * dt * speedRatio

            -- 몸통은 수평 유지(좌우 흔들림 제거 → '춤추는' 느낌 없음).
            -- 아주 약한 상하 bob 만 살짝 더해 생동감만.
            local bobY = Wander.bobHeight * math.abs(math.sin(s.phase)) * speedRatio

            -- ── 최종 ground CFrame 조립 및 배치 ───────────────────
            local groundCF = CFrame.new(Vector3.new(newPos.X, groundY + bobY, newPos.Z))
                * CFrame.Angles(0, s.yaw, 0)

            AlpacaSpawner.placeOnGround(model, groundCF)

            -- ── 다리 앞뒤 스윙(보행) ──────────────────────────────
            -- PivotTo 직후 root(=PrimaryPart) 기준으로 각 다리를 덮어써 걷는 모션 생성.
            -- 진폭은 속도에 비례 → 빠를수록 성큼성큼, 멈추면 자연히 0.
            applyLegPose(s.legs, primary.CFrame, Wander.legSwing * speedRatio, s.phase)
        end
    end
end

-- =====================================================================
-- 공개 API
-- =====================================================================

--- 서버 Main 에서 호출. Heartbeat 루프를 등록합니다.
function AlpacaAI.init()
    RunService.Heartbeat:Connect(onHeartbeat)
end

--- 케어 반응을 트리거합니다.
--- Heartbeat 루프에서 GameConfig.CareReaction.duration 초간 깡총 반응을
--- 수행하고, 이후 자동으로 배회를 재개합니다.
---
--- @param model    케어를 받은 알파카 모델
--- @param careType 케어 종류 문자열 (확장용, 현재 미사용)
--- @param byPlayer 케어를 수행한 플레이어 (facePlayer 방향 계산용)
function AlpacaAI.reactToCare(model: Model, careType: string?, byPlayer: Player?)
    -- 안전 가드: nil 또는 부모 없는 모델 → 에러 없이 조용히 반환
    if model == nil or model.Parent == nil then return end
    local primary = model.PrimaryPart
    if primary == nil then return end

    local now = os.clock()

    -- state 가 아직 없으면 임시 생성 (Heartbeat 이전에 호출될 수 있음)
    if not state[model] then
        local pivot   = model:GetPivot()
        local pos     = pivot.Position
        local lv      = pivot.LookVector
        local initYaw = math.atan2(-lv.X, -lv.Z)
        state[model] = {
            target     = pos,
            pauseUntil = 0,
            speed      = 0,
            yaw        = initYaw,
            phase      = 0,
            legs       = collectLegs(model, primary),
            reactUntil = 0,
            reactPhase = 0,
            faceYaw    = initYaw,
        }
    end

    local s = state[model]

    -- 반응 시작 (이전 반응이 진행 중이었으면 덮어씀)
    s.reactUntil = now + CareReaction.duration
    s.reactPhase = 0
    s.speed      = 0   -- 이동 중이었다면 즉시 정지

    -- facePlayer: 케어한 플레이어를 향하는 yaw 계산
    if CareReaction.facePlayer and byPlayer ~= nil then
        local char: Model? = byPlayer.Character
        if char ~= nil then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp ~= nil and hrp:IsA("BasePart") then
                s.faceYaw = yawToward(model:GetPivot().Position, (hrp :: BasePart).Position)
            else
                s.faceYaw = s.yaw
            end
        else
            s.faceYaw = s.yaw
        end
    else
        s.faceYaw = s.yaw
    end

    -- 알파카 머리 위 '💕' 플로팅 BillboardGui
    -- Debris:AddItem 으로 duration 후 자동 정리 → 메모리 누수 없음
    local gui         = Instance.new("BillboardGui")
    gui.Name          = "CareReactionGui"
    gui.Size          = UDim2.new(0, 60, 0, 40)
    gui.StudsOffset   = Vector3.new(0, 5, 0)
    gui.AlwaysOnTop   = false
    gui.Adornee       = primary
    gui.Parent        = primary

    local label                  = Instance.new("TextLabel")
    label.Size                   = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text                   = "💕"
    label.TextScaled             = true
    label.Font                   = Enum.Font.GothamBold
    label.Parent                 = gui

    Debris:AddItem(gui, CareReaction.duration)

    -- 케어 종류별 효과음을 알파카 PrimaryPart 에서 서버가 재생.
    -- → 위치 기반으로 복제되어 주변 모든 플레이어(친구 포함)가 듣는다.
    --   feed=오물오물(씹기), brush=빗질, bath=첨벙. (소리 ID 는 GameConfig.Sounds)
    if careType ~= nil then
        local soundId = GameConfig.careSound(careType)
        if soundId ~= "" then
            local sfx              = Instance.new("Sound")
            sfx.Name               = "CareSound"
            sfx.SoundId            = soundId
            sfx.Volume             = GameConfig.Sounds.volume
            sfx.RollOffMaxDistance = 80
            if careType == "feed" then
                sfx.PlaybackSpeed = 1.2  -- 살짝 빠르게 → 오물오물 씹는 느낌
                sfx.Looped        = true -- 반응 시간 동안 반복
            end
            sfx.Parent = primary
            sfx:Play()
            Debris:AddItem(sfx, CareReaction.duration) -- duration 후 자동 제거(=정지)
        end
    end
end

return AlpacaAI
