--!strict
--[[
	AlpacaSpawner
	-------------
	GameConfig.Alpacas 정의를 받아 "블록형 귀여운 알파카" 모델을 코드로 조립합니다.
	외부 에셋 없이 Part만 사용하며, 등급별로 색/크기/장식이 달라집니다.

	계약(다른 모듈이 의존하는 규칙):
	- 모델 이름 = defId, PrimaryPart = "Root"(몸통 중심).
	- 모든 파트는 Anchored=true. 이동은 AI가 model:PivotTo 로 처리.
	- 모델 속성(SetAttribute):
		AlpacaId, Uid, OwnerUserId, Hunger, Tangle, Dirt, Happiness, Wool, GroundOffset
	- 바닥에 세울 때는 AlpacaSpawner.placeOnGround(model, groundCFrame) 사용
	  (groundCFrame 위치에 발이 닿도록 GroundOffset 만큼 올려 배치).
	- 상태 외형 갱신은 AlpacaSpawner.updateVisual(model, hunger, tangle, dirt).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local AlpacaSpawner = {}

export type SpawnArgs = {
	defId: string,
	uid: string,
	ownerUserId: number,
	hunger: number,
	tangle: number,
	dirt: number,
	happiness: number,
	wool: number,
	name: string?,
	accessory: string?, -- 착용 악세사리 id(없으면 nil)
}

-- 기준 치수(scale=1). 모든 값에 def.scale 을 곱함.
local BODY_H = 3.2
local BODY_L = 4.6
local BODY_W = 2.6
local LEG_H = 2.4
local LEG_S = 0.75
local NECK_H = 4.8 -- 알파카는 목이 긺(기존 2.6) → 머리/귀 위치는 자동 상향
local NECK_S = 1.0 -- 긴 목은 살짝 가늘게
local HEAD = 1.7

local function newPart(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- defId 로 알파카 모델 생성 (모든 좌표는 발=y0 인 로컬 공간)
function AlpacaSpawner.build(args: SpawnArgs): Model
	local def = GameConfig.AlpacasById[args.defId]
	assert(def, "알 수 없는 알파카 defId: " .. tostring(args.defId))

	local s = def.scale
	local body = Color3.new(def.bodyColor.R, def.bodyColor.G, def.bodyColor.B)
	local accent = Color3.new(def.accentColor.R, def.accentColor.G, def.accentColor.B)
	local bodyMat = def.features.glow and Enum.Material.Neon or Enum.Material.SmoothPlastic

	local model = Instance.new("Model")
	model.Name = def.id

	local groundOffset = (LEG_H + BODY_H / 2) * s

	-- 몸통(= Root, PrimaryPart)
	local root = newPart("Root", Vector3.new(BODY_W, BODY_H, BODY_L) * s, Vector3.new(0, groundOffset, 0), body, bodyMat, model)
	model.PrimaryPart = root

	-- 다리 4개 (앞=-Z, 뒤=+Z)
	local legY = (LEG_H / 2) * s
	local legX = (BODY_W / 2 - LEG_S) * s
	local legZ = (BODY_L / 2 - LEG_S * 1.5) * s
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local leg = newPart(
				"Leg",
				Vector3.new(LEG_S, LEG_H, LEG_S) * s,
				Vector3.new(sx * legX, legY, sz * legZ),
				body,
				Enum.Material.SmoothPlastic,
				model
			)
			-- 발굽
			newPart(
				"Hoof",
				Vector3.new(LEG_S + 0.15, 0.5, LEG_S + 0.15) * s,
				Vector3.new(sx * legX, 0.25 * s, sz * legZ),
				accent,
				Enum.Material.SmoothPlastic,
				model
			)
			leg:SetAttribute("part", "leg")
		end
	end

	-- 목 (앞쪽 위로) — 약간 기울임
	local neckY = (LEG_H + BODY_H * 0.5 + NECK_H * 0.4) * s
	local neckZ = -(BODY_L / 2 - NECK_S) * s
	local neck = newPart("Neck", Vector3.new(NECK_S, NECK_H, NECK_S) * s, Vector3.new(0, neckY, neckZ), body, bodyMat, model)
	neck.CFrame = CFrame.new(neck.Position) * CFrame.Angles(math.rad(-12), 0, 0) -- 더 곧게 세움(긴 목)

	-- 머리
	local headY = (LEG_H + BODY_H * 0.5 + NECK_H * 0.85) * s
	local headZ = neckZ - (NECK_H * 0.18) * s
	newPart("Head", Vector3.new(HEAD, HEAD, HEAD) * s, Vector3.new(0, headY, headZ), body, bodyMat, model)

	-- 주둥이
	newPart("Snout", Vector3.new(HEAD * 0.6, HEAD * 0.45, HEAD * 0.5) * s, Vector3.new(0, headY - 0.2 * s, headZ - HEAD * 0.55 * s), accent, Enum.Material.SmoothPlastic, model)

	-- 귀 2개
	for _, sx in ipairs({ -1, 1 }) do
		newPart("Ear", Vector3.new(0.45, HEAD * 0.7, 0.55) * s, Vector3.new(sx * HEAD * 0.32 * s, headY + HEAD * 0.65 * s, headZ + 0.1 * s), accent, Enum.Material.SmoothPlastic, model)
	end

	-- 눈 2개
	for _, sx in ipairs({ -1, 1 }) do
		newPart("Eye", Vector3.new(0.28, 0.28, 0.2) * s, Vector3.new(sx * HEAD * 0.26 * s, headY + 0.15 * s, headZ - HEAD * 0.5 * s), Color3.fromRGB(25, 20, 20), Enum.Material.SmoothPlastic, model)
	end

	-- 정수리 양털 뭉치
	for i = -1, 1 do
		newPart("Fluff", Vector3.new(0.8, 0.7, 0.8) * s, Vector3.new(i * 0.55 * s, headY + HEAD * 0.6 * s, headZ + HEAD * 0.25 * s), body, Enum.Material.SmoothPlastic, model)
	end
	-- 등 양털
	newPart("BackFluff", Vector3.new(BODY_W * 0.9, 0.9, BODY_L * 0.8) * s, Vector3.new(0, (LEG_H + BODY_H) * s, 0), body, Enum.Material.SmoothPlastic, model)

	-- 꼬리
	newPart("Tail", Vector3.new(0.7, 0.7, 0.7) * s, Vector3.new(0, (LEG_H + BODY_H * 0.4) * s, (BODY_L / 2) * s), body, Enum.Material.SmoothPlastic, model)

	-- ===== 등급 장식 =====
	-- 뿔 (유니콘)
	if def.features.horn then
		local horn = newPart("Horn", Vector3.new(0.4, HEAD * 1.1, 0.4) * s, Vector3.new(0, headY + HEAD * 0.95 * s, headZ - HEAD * 0.3 * s), Color3.fromRGB(255, 235, 150), Enum.Material.Neon, model)
		horn.CFrame = CFrame.new(horn.Position) * CFrame.Angles(math.rad(-20), 0, 0)
	end
	-- 왕관 (전설 등)
	if def.features.crown then
		local crownY = headY + HEAD * 0.7 * s
		for k = 0, 5 do
			local ang = math.rad(k * 60)
			newPart("Crown", Vector3.new(0.35, 0.9, 0.35) * s, Vector3.new(math.sin(ang) * HEAD * 0.4 * s, crownY, headZ + math.cos(ang) * HEAD * 0.4 * s), Color3.fromRGB(255, 215, 80), Enum.Material.Neon, model)
		end
	end
	-- 반짝임
	if def.features.sparkle then
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = accent
		sp.Parent = root
	end
	-- 발광
	if def.features.glow then
		local light = Instance.new("PointLight")
		light.Color = body
		light.Range = 14
		light.Brightness = 2
		light.Parent = root
	end

	-- ===== 상태 외형(기본 숨김) =====
	local dirtFolder = Instance.new("Folder")
	dirtFolder.Name = "DirtDecor"
	dirtFolder.Parent = model
	for i = 1, 4 do
		local px = (i % 2 == 0 and 1 or -1) * BODY_W * 0.4 * s
		local pz = (i <= 2 and -1 or 1) * BODY_L * 0.25 * s
		local blot = newPart("Dirt", Vector3.new(0.9, 0.5, 0.9) * s, Vector3.new(px, (LEG_H + BODY_H * 0.3) * s, pz), Color3.fromRGB(110, 84, 54), Enum.Material.Sand, dirtFolder)
		blot.Transparency = 1
	end

	local tangleFolder = Instance.new("Folder")
	tangleFolder.Name = "TangleDecor"
	tangleFolder.Parent = model
	local tangleColor = Color3.new(body.R * 0.7, body.G * 0.7, body.B * 0.7)
	for i = 1, 5 do
		local ang = math.rad(i * 72)
		local knot = newPart("Tangle", Vector3.new(0.7, 0.7, 0.7) * s, Vector3.new(math.sin(ang) * BODY_W * 0.45 * s, (LEG_H + BODY_H * 0.9) * s, math.cos(ang) * BODY_L * 0.4 * s), tangleColor, Enum.Material.SmoothPlastic, tangleFolder)
		knot.Transparency = 1
		knot.CFrame = CFrame.new(knot.Position) * CFrame.Angles(math.rad(20 * i), math.rad(15 * i), 0)
	end

	-- ===== 속성 =====
	model:SetAttribute("AlpacaId", def.id)
	model:SetAttribute("Uid", args.uid)
	model:SetAttribute("OwnerUserId", args.ownerUserId)
	model:SetAttribute("Hunger", args.hunger)
	model:SetAttribute("Tangle", args.tangle)
	model:SetAttribute("Dirt", args.dirt)
	model:SetAttribute("Happiness", args.happiness)
	model:SetAttribute("Wool", args.wool)
	model:SetAttribute("GroundOffset", groundOffset)
	AlpacaSpawner.setNickname(model, args.name)

	AlpacaSpawner.updateVisual(model, args.hunger, args.tangle, args.dirt)
	AlpacaSpawner.applyAccessory(model, args.accessory)
	return model
end

-- 알파카에 악세사리(옷/장신구) 파트를 부착/교체.
-- 기존 "AccessoryDecor" 폴더를 지우고 accId 의 kind 에 맞춰 새로 조립한다.
-- accId 가 nil/"" 이면 벗긴다. 모든 파트는 Anchored=true 라 모델 PivotTo 이동을 따라간다.
function AlpacaSpawner.applyAccessory(model: Model, accId: string?)
	local old = model:FindFirstChild("AccessoryDecor")
	if old then
		old:Destroy()
	end
	model:SetAttribute("Accessory", accId or "")
	if not accId or accId == "" then
		return
	end
	local acc = GameConfig.AccessoriesById[accId]
	if not acc then
		return
	end

	local alpacaId = model:GetAttribute("AlpacaId") :: string?
	local def = (alpacaId and GameConfig.AlpacasById[alpacaId]) or nil
	local s = (def and def.scale) or 1

	local head = model:FindFirstChild("Head") :: BasePart?
	local neck = model:FindFirstChild("Neck") :: BasePart?
	local root = model.PrimaryPart
	if not head or not root then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "AccessoryDecor"
	folder.Parent = model

	local V3 = Vector3.new
	local Block = Enum.PartType.Block
	local Cyl = Enum.PartType.Cylinder
	local Ball = Enum.PartType.Ball
	local color = acc.color
	local accent = acc.accent or acc.color

	local function mk(name: string, shape: Enum.PartType, size: Vector3, baseCF: CFrame, relCF: CFrame, c: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Anchored = true
		p.CanCollide = false
		p.Massless = true
		p.Size = size
		p.Color = c
		p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = baseCF * relCF
		p.Parent = folder
		return p
	end

	local headCF = head.CFrame
	local half = HEAD * s * 0.5
	local lay = CFrame.Angles(0, 0, math.rad(90)) -- 원기둥을 눕혀(원판이 위를 보게) 배치

	if acc.kind == "hat" then
		mk("AccBrim", Cyl, V3(0.3 * s, HEAD * 1.85 * s, HEAD * 1.85 * s), headCF, CFrame.new(0, half + 0.15 * s, 0) * lay, color, Enum.Material.Fabric)
		mk("AccTop", Cyl, V3(HEAD * 0.7 * s, HEAD * 1.0 * s, HEAD * 1.0 * s), headCF, CFrame.new(0, half + 0.15 * s + HEAD * 0.35 * s, 0) * lay, color, Enum.Material.Fabric)
		mk("AccBand", Cyl, V3(HEAD * 0.22 * s, HEAD * 1.06 * s, HEAD * 1.06 * s), headCF, CFrame.new(0, half + 0.2 * s, 0) * lay, accent, Enum.Material.SmoothPlastic)
	elseif acc.kind == "tophat" then
		mk("AccBrim", Cyl, V3(0.3 * s, HEAD * 1.7 * s, HEAD * 1.7 * s), headCF, CFrame.new(0, half + 0.15 * s, 0) * lay, color, Enum.Material.SmoothPlastic)
		mk("AccBarrel", Cyl, V3(HEAD * 1.5 * s, HEAD * 1.05 * s, HEAD * 1.05 * s), headCF, CFrame.new(0, half + 0.15 * s + HEAD * 0.75 * s, 0) * lay, color, Enum.Material.SmoothPlastic)
		mk("AccBand", Cyl, V3(HEAD * 0.26 * s, HEAD * 1.1 * s, HEAD * 1.1 * s), headCF, CFrame.new(0, half + 0.32 * s, 0) * lay, accent, Enum.Material.SmoothPlastic)
	elseif acc.kind == "bow" then
		local y = half + 0.25 * s
		mk("AccBowL", Block, V3(HEAD * 0.55 * s, HEAD * 0.5 * s, 0.35 * s), headCF, CFrame.new(-HEAD * 0.45 * s, y, 0) * CFrame.Angles(0, 0, math.rad(22)), color, Enum.Material.SmoothPlastic)
		mk("AccBowR", Block, V3(HEAD * 0.55 * s, HEAD * 0.5 * s, 0.35 * s), headCF, CFrame.new(HEAD * 0.45 * s, y, 0) * CFrame.Angles(0, 0, math.rad(-22)), color, Enum.Material.SmoothPlastic)
		mk("AccBowKnot", Block, V3(HEAD * 0.28 * s, HEAD * 0.28 * s, 0.42 * s), headCF, CFrame.new(0, y, 0), accent, Enum.Material.SmoothPlastic)
	elseif acc.kind == "scarf" then
		local base = (neck and neck.CFrame) or headCF
		mk("AccScarf", Block, V3(NECK_S * 2.4 * s, NECK_H * 0.26 * s, NECK_S * 2.4 * s), base, CFrame.new(0, -NECK_H * 0.28 * s, 0), color, Enum.Material.Fabric)
		mk("AccScarfTail", Block, V3(NECK_S * 0.9 * s, NECK_H * 0.5 * s, 0.35 * s), base, CFrame.new(0, -NECK_H * 0.5 * s, -NECK_S * 1.0 * s), accent, Enum.Material.Fabric)
	elseif acc.kind == "glasses" then
		local z = -(half + 0.08 * s)
		mk("AccLensL", Block, V3(HEAD * 0.42 * s, HEAD * 0.34 * s, 0.18 * s), headCF, CFrame.new(-HEAD * 0.28 * s, 0.12 * s, z), color, Enum.Material.SmoothPlastic)
		mk("AccLensR", Block, V3(HEAD * 0.42 * s, HEAD * 0.34 * s, 0.18 * s), headCF, CFrame.new(HEAD * 0.28 * s, 0.12 * s, z), color, Enum.Material.SmoothPlastic)
		mk("AccBridge", Block, V3(HEAD * 0.24 * s, 0.12 * s, 0.16 * s), headCF, CFrame.new(0, 0.12 * s, z), accent, Enum.Material.SmoothPlastic)
	elseif acc.kind == "flower" then
		local y = half - 0.02 * s
		local r = HEAD * 0.55 * s
		for k = 0, 5 do
			local a = math.rad(k * 60)
			local c = (k % 2 == 0) and color or accent
			mk("AccFlower", Ball, V3(HEAD * 0.42 * s, HEAD * 0.42 * s, HEAD * 0.42 * s), headCF, CFrame.new(math.sin(a) * r, y, math.cos(a) * r), c, Enum.Material.SmoothPlastic)
		end
	elseif acc.kind == "crown" then
		local y = half + 0.38 * s
		local r = HEAD * 0.42 * s
		mk("AccCrownBand", Cyl, V3(0.28 * s, HEAD * 1.0 * s, HEAD * 1.0 * s), headCF, CFrame.new(0, half + 0.12 * s, 0) * lay, color, Enum.Material.Neon)
		for k = 0, 5 do
			local a = math.rad(k * 60)
			mk("AccCrown", Block, V3(0.3 * s, HEAD * 0.7 * s, 0.3 * s), headCF, CFrame.new(math.sin(a) * r, y, math.cos(a) * r), color, Enum.Material.Neon)
		end
		mk("AccGem", Ball, V3(0.36 * s, 0.36 * s, 0.36 * s), headCF, CFrame.new(0, y, -r), accent, Enum.Material.Neon)
	elseif acc.kind == "cape" then
		local base = root.CFrame
		mk("AccCapeTop", Block, V3(BODY_W * 1.05 * s, 0.3 * s, BODY_L * 0.85 * s), base, CFrame.new(0, BODY_H * 0.52 * s, 0), color, Enum.Material.Fabric)
		mk("AccCapeBack", Block, V3(BODY_W * 1.0 * s, BODY_H * 0.95 * s, 0.3 * s), base, CFrame.new(0, BODY_H * 0.05 * s, BODY_L * 0.5 * s), color, Enum.Material.Fabric)
		mk("AccCapeCollar", Block, V3(BODY_W * 0.6 * s, 0.42 * s, 0.5 * s), base, CFrame.new(0, BODY_H * 0.55 * s, -BODY_L * 0.4 * s), accent, Enum.Material.SmoothPlastic)
	end
end

-- 발이 groundCFrame 위치에 닿도록 모델 배치 (방향은 groundCFrame 유지)
function AlpacaSpawner.placeOnGround(model: Model, groundCFrame: CFrame)
	local offset = model:GetAttribute("GroundOffset") or 4
	model:PivotTo(groundCFrame * CFrame.new(0, offset, 0))
end

-- 머리 위 이름표(영구 BillboardGui) 생성/갱신.
-- name 이 비면 종 이름(displayName)으로 대체해 항상 라벨이 보이도록 함.
function AlpacaSpawner.setNickname(model: Model, name: string?)
	model:SetAttribute("Nickname", name or "")

	local alpacaId = model:GetAttribute("AlpacaId") :: string?
	local def = (alpacaId and GameConfig.AlpacasById[alpacaId]) or nil
	local display = (name ~= nil and name ~= "" and name) or (def and def.displayName) or "알파카"

	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local tag = head:FindFirstChild("NameTag") :: BillboardGui?
	if not tag then
		local newTag = Instance.new("BillboardGui")
		newTag.Name = "NameTag"
		newTag.Adornee = head
		newTag.AlwaysOnTop = true
		newTag.Size = UDim2.new(0, 190, 0, 44)
		newTag.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.6 + 1.9, 0)
		newTag.MaxDistance = 140
		newTag.Parent = head

		local lbl = Instance.new("TextLabel")
		lbl.Name = "NameLabel"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextStrokeColor3 = Color3.fromRGB(60, 40, 20)
		lbl.TextStrokeTransparency = 0.1
		lbl.Parent = newTag

		local sizeCap = Instance.new("UITextSizeConstraint")
		sizeCap.MaxTextSize = 22
		sizeCap.Parent = lbl

		tag = newTag
	end

	local label = tag:FindFirstChild("NameLabel") :: TextLabel?
	if label then
		label.Text = display
	end
end

-- 욕구에 따라 얼룩/엉킨 털 표시 토글
function AlpacaSpawner.updateVisual(model: Model, hunger: number, tangle: number, dirt: number)
	local thresholds = GameConfig.Care.visualThreshold
	local dirtFolder = model:FindFirstChild("DirtDecor")
	if dirtFolder then
		local show = dirt >= thresholds.Dirt
		for _, p in ipairs(dirtFolder:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = show and 0.15 or 1
			end
		end
	end
	local tangleFolder = model:FindFirstChild("TangleDecor")
	if tangleFolder then
		local show = tangle >= thresholds.Tangle
		for _, p in ipairs(tangleFolder:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = show and 0 or 1
			end
		end
	end
end

return AlpacaSpawner
