--!strict
--[[
	VehicleService (서버)
	---------------------
	플레이어가 타고 다닐 수 있는 귀여운 "농장 카트"를 소환/정리합니다.
	- 차고 패드(GaragePad)를 밟으면 카트가 소환되고 자동으로 탑승
	- VehicleSeat 를 차체(PrimaryPart)로 쓰고, 그 위에 차체/바퀴를 용접
	- 실제 주행 물리는 클라이언트(VehicleController)가 담당 (시트 Throttle/Steer 입력 → 속도/회전)
	  → 그래서 네트워크 소유권을 운전자에게 넘긴다 (반응성 + 클라가 AssemblyLinearVelocity 제어 가능)

	좌표 규약: 시트 로컬 전진 = -Z (LookVector). 앞(후드/헤드라이트) = -Z, 뒤 = +Z.

	참고: my-first-cargame 의 CarSpawner/CarController 의 검증된 물리 코어만 떼어내
	      레이싱 요소(부스트/아이템/커스터마이징/오디오설정)를 모두 제거한 단순화 버전.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local FarmBuilder = require(ServerScriptService.FarmBuilder)

local VehicleService = {}

-- 성능(클라 컨트롤러가 어트리뷰트로 읽음)
local KART_SPEED = 62 -- 최고 전진 속도
local KART_ACCEL = 50 -- 가속 반응성
local KART_TURN = 2.6 -- 회전 속도

-- userId -> 현재 소환된 카트
local activeKart: { [number]: Model } = {}

-- =====================================================================
-- 조립 헬퍼
-- =====================================================================
local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- 시트에 용접되는 장식 파트 (충돌 없음 / 질량 없음)
local function decor(model: Model, seat: BasePart, offset: CFrame, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.CFrame = seat.CFrame * offset
	p.Parent = model
	weld(seat, p)
	return p
end

-- 바퀴 4개 (장식 — 충돌은 시트 본체가 담당)
local function buildWheels(model: Model, seat: BasePart)
	local hw = 2.5 + 0.1 -- 시트 폭(5)의 절반 + 약간 바깥
	local axleZ = 2.6
	local wheelY = 0.4 -- 시트 중심 기준 (반경 1.0 → 바닥이 시트 바닥 근처)
	for _, sx in ipairs({ 1, -1 }) do
		for _, sz in ipairs({ 1, -1 }) do
			local tire = Instance.new("Part")
			tire.Name = "Wheel"
			tire.Shape = Enum.PartType.Cylinder -- 로컬 X축이 원통 축 → 원형 면이 좌우(±X)
			tire.Size = Vector3.new(0.9, 2.0, 2.0) -- 두께 0.9, 지름 2.0
			tire.Color = Color3.fromRGB(32, 32, 38)
			tire.Material = Enum.Material.SmoothPlastic
			tire.Anchored = false
			tire.CanCollide = false
			tire.Massless = true
			tire.TopSurface = Enum.SurfaceType.Smooth
			tire.BottomSurface = Enum.SurfaceType.Smooth
			tire.CFrame = seat.CFrame * CFrame.new(sx * hw, wheelY, sz * axleZ)
			tire.Parent = model
			weld(seat, tire)
		end
	end
end

-- 카트 모델 조립 (PrimaryPart = VehicleSeat)
local function buildKart(ownerName: string): Model
	local model = Instance.new("Model")
	model.Name = "AlpacaKart"

	local bodyColor = Color3.fromRGB(245, 170, 70)
	local trim = Color3.fromRGB(74, 52, 32)

	-- 차체 = VehicleSeat (탑승 + 충돌 본체)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "KartSeat"
	seat.Size = Vector3.new(5, 1.2, 8)
	seat.Color = bodyColor
	seat.Material = Enum.Material.SmoothPlastic
	seat.MaxSpeed = KART_SPEED
	seat.Torque = 0 -- 직접 물리 제어하므로 시트 기본 구동은 끔
	seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = model
	model.PrimaryPart = seat

	-- 후드(앞)
	decor(model, seat, CFrame.new(0, 0.3, -3.2), {
		Size = Vector3.new(4.4, 1.0, 2.6),
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	-- 앞 범퍼
	decor(model, seat, CFrame.new(0, -0.1, -4.3), {
		Size = Vector3.new(4.8, 1.0, 0.8),
		Color = trim,
		Material = Enum.Material.SmoothPlastic,
	})
	-- 헤드라이트 좌우
	for _, sx in ipairs({ 1, -1 }) do
		decor(model, seat, CFrame.new(sx * 1.5, 0.4, -4.2), {
			Size = Vector3.new(0.8, 0.5, 0.3),
			Color = Color3.fromRGB(255, 246, 205),
			Material = Enum.Material.Neon,
		})
	end
	-- 운전석 등받이
	decor(model, seat, CFrame.new(0, 1.3, 2.6), {
		Size = Vector3.new(4.0, 2.2, 0.6),
		Color = trim,
		Material = Enum.Material.SmoothPlastic,
	})
	-- 롤바(등받이 위 보호 바)
	for _, sx in ipairs({ 1, -1 }) do
		decor(model, seat, CFrame.new(sx * 1.7, 2.2, 2.7), {
			Size = Vector3.new(0.35, 2.0, 0.35),
			Color = Color3.fromRGB(90, 92, 100),
			Material = Enum.Material.Metal,
		})
	end
	-- 뒤 트렁크
	decor(model, seat, CFrame.new(0, 0.3, 3.6), {
		Size = Vector3.new(4.4, 1.1, 1.2),
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	-- 테일라이트
	decor(model, seat, CFrame.new(0, 0.5, 4.25), {
		Size = Vector3.new(3.4, 0.4, 0.2),
		Color = Color3.fromRGB(235, 60, 60),
		Material = Enum.Material.Neon,
	})

	buildWheels(model, seat)

	-- 이름표 (카트 위 떠 있는 BillboardGui)
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "KartName"
	nameGui.Size = UDim2.fromOffset(190, 44)
	nameGui.StudsOffset = Vector3.new(0, 3.6, 0)
	nameGui.AlwaysOnTop = false
	nameGui.MaxDistance = 200
	nameGui.Adornee = seat
	nameGui.Parent = seat
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "🛺 " .. ownerName
	nameLabel.TextColor3 = Color3.fromRGB(255, 248, 230)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.Parent = nameGui

	-- 클라 컨트롤러가 읽는 어트리뷰트
	seat:SetAttribute("IsAlpacaKart", true)
	seat:SetAttribute("KartSpeed", KART_SPEED)
	seat:SetAttribute("KartAccel", KART_ACCEL)
	seat:SetAttribute("KartTurn", KART_TURN)

	return model
end

-- =====================================================================
-- 소환 / 정리
-- =====================================================================

-- 플레이어의 기존 카트 제거
function VehicleService.removeKart(player: Player)
	local m = activeKart[player.UserId]
	if m then
		m:Destroy()
		activeKart[player.UserId] = nil
	end
end

-- 플레이어용 카트 소환 + 탑승
function VehicleService.spawnFor(player: Player)
	local cf = FarmBuilder.getKartSpawnCFrame()
	if not cf then
		return
	end
	-- 이전 카트 정리 (1인 1카트)
	VehicleService.removeKart(player)

	local model = buildKart(player.Name)
	model:PivotTo(cf)
	model.Parent = workspace
	activeKart[player.UserId] = model
	model:SetAttribute("OwnerUserId", player.UserId)

	local seat = model.PrimaryPart :: VehicleSeat
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			task.defer(function()
				if seat.Parent then
					seat:Sit(humanoid)
				end
			end)
		end
	end

	-- 네트워크 소유권을 운전자에게 (클라가 주행 물리 제어)
	task.defer(function()
		pcall(function()
			seat:SetNetworkOwner(player)
		end)
	end)
end

-- =====================================================================
-- 초기화
-- =====================================================================
function VehicleService.init()
	local pad = FarmBuilder.getGaragePad()
	if pad then
		local lastUse: { [number]: number } = {}
		pad.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			if not character then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			-- 이미 어떤 시트에 앉아 있으면 무시 (소환된 카트가 패드를 건드려 재소환되는 것 방지)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat") then
				return
			end
			local now = os.clock()
			if lastUse[player.UserId] and now - lastUse[player.UserId] < 3 then
				return
			end
			lastUse[player.UserId] = now
			VehicleService.spawnFor(player)
		end)
	end

	-- 퇴장 / 캐릭터 리셋(사망·리스폰) 시 카트 정리
	Players.PlayerRemoving:Connect(function(player)
		VehicleService.removeKart(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			VehicleService.removeKart(player)
		end)
	end)
end

return VehicleService
