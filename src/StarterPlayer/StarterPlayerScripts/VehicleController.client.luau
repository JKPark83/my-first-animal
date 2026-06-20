--!strict
--[[
	VehicleController (클라이언트)
	------------------------------
	농장 카트의 아케이드 주행 물리를 담당합니다.
	- 플레이어가 카트(VehicleSeat, 어트리뷰트 IsAlpacaKart)에 탑승하면 활성화
	- 시트의 ThrottleFloat/SteerFloat(WASD) 입력을 읽어 속도/회전 제어
	- 네트워크 소유권이 운전자에게 있어 AssemblyLinearVelocity 제어가 부드럽게 반영됨
	- 카트에서 내리려면 점프(Space) — VehicleSeat 기본 동작

	평면 주행: 수평 속도는 직접 제어, 수직(Y)은 중력에 맡긴다.
	참고: my-first-cargame CarController 의 핵심 물리만 단순화해 가져옴.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local activeSeat: VehicleSeat? = nil
local currentSpeed = 0 -- 현재 전진 속도(음수 = 후진)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 현재 탑승 중인 카트 시트 찾기
local function findKartSeat(): VehicleSeat?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local seatPart = humanoid.SeatPart
	if seatPart and seatPart:IsA("VehicleSeat") and seatPart:GetAttribute("IsAlpacaKart") == true then
		return seatPart
	end
	return nil
end

RunService.Heartbeat:Connect(function(dt: number)
	-- 활성 시트 갱신
	local seat = findKartSeat()
	if seat ~= activeSeat then
		activeSeat = seat
		currentSpeed = 0
	end
	if not seat then
		return
	end
	if seat.Anchored then
		currentSpeed = 0
		return
	end

	local topSpeed = (seat:GetAttribute("KartSpeed") :: number?) or 62
	local accel = (seat:GetAttribute("KartAccel") :: number?) or 50
	local turn = (seat:GetAttribute("KartTurn") :: number?) or 2.6

	-- 입력 (VehicleSeat 가 WASD 를 -1~1 범위로 제공)
	local throttle = seat.ThrottleFloat
	local steer = seat.SteerFloat

	-- 목표 속도 (후진은 최고속의 40% 제한)
	local target: number
	if throttle ~= 0 then
		local maxForThrottle = throttle > 0 and topSpeed or topSpeed * 0.4
		target = throttle * maxForThrottle
	else
		target = 0
	end

	-- 가속/감속
	local rate = math.clamp(accel * dt * 0.12, 0, 1)
	if target == 0 then
		rate = math.clamp(dt * 1.6, 0, 1) -- 관성 감속
	end
	currentSpeed = lerp(currentSpeed, target, rate)
	if math.abs(currentSpeed) < 0.5 then
		currentSpeed = 0
	end

	-- 전진 방향으로 수평 속도 적용 (수직 성분은 중력)
	local cf = seat.CFrame
	local forward = cf.LookVector
	local horizontal = Vector3.new(forward.X, 0, forward.Z)
	if horizontal.Magnitude > 0 then
		horizontal = horizontal.Unit
	end
	local vy = seat.AssemblyLinearVelocity.Y
	local desired = horizontal * currentSpeed
	seat.AssemblyLinearVelocity = Vector3.new(desired.X, vy, desired.Z)

	-- 속도 비례 회전 (정지 시 회전 약함)
	local speedFactor = math.clamp(math.abs(currentSpeed) / topSpeed, 0, 1)
	local turnRate = turn * (0.25 + 0.75 * speedFactor)
	local direction = currentSpeed >= 0 and 1 or -1
	seat.AssemblyAngularVelocity = Vector3.new(0, -steer * turnRate * direction, 0)
end)

print("[VehicleController] 농장 카트 컨트롤러 준비 완료 🛺")
