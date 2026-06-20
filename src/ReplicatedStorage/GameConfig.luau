--!strict
--[[
	GameConfig
	-----------
	게임의 모든 핵심 데이터를 한곳에 모은 설정 모듈입니다.
	알파카 종류 / 가격 / 케어 보상 / 양털 수익 / 욕구 속도 / 슬롯 / 경제 /
	리더보드 / 로벅스(GamePass) 옵션을 여기서 관리하면 밸런스 조정이 쉬워집니다.

	이 모듈은 서버와 클라이언트 양쪽에서 require 하여 공유합니다.

	▶ 밸런스를 바꾸고 싶다면 거의 모든 수치가 이 파일 한 곳에 있습니다.
]]

local GameConfig = {}

-- =====================================================================
-- 등급(희귀도) — 알파카 카드 테두리 색 / 정렬용
-- =====================================================================
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

GameConfig.Rarities = {
	Common = { displayName = "일반", color = Color3.fromRGB(170, 180, 190), order = 1 },
	Uncommon = { displayName = "고급", color = Color3.fromRGB(120, 200, 120), order = 2 },
	Rare = { displayName = "희귀", color = Color3.fromRGB(90, 160, 240), order = 3 },
	Epic = { displayName = "에픽", color = Color3.fromRGB(180, 110, 240), order = 4 },
	Legendary = { displayName = "전설", color = Color3.fromRGB(245, 200, 80), order = 5 },
	Mythic = { displayName = "신화", color = Color3.fromRGB(255, 120, 170), order = 6 },
}

-- =====================================================================
-- 알파카 목록
-- =====================================================================
-- price       : 게임머니 가격 (currency == "Money")
-- careReward  : 케어 1회당 지급 머니 (먹이/빗질/목욕 각각)
-- woolValue   : 양털 1주기(WoolConfig.cycle 초)마다 적립되는 머니(행복도 100 기준)
-- currency    : "Money" = 게임머니 / "Robux" = 로벅스 전용(현재 비활성, 구조만)
-- robuxPrice  : 로벅스 표시 가격(참고용)
-- robuxProductId : 출시 시 연결할 GamePass/DevProduct id (nil = 미연결)
-- countInDex  : 도감 10종에 포함되는지 (로벅스 한정 알파카는 false)
-- 외형:
--   bodyColor / accentColor : 몸/장식 색
--   scale       : 전체 크기 배수 (1.0 기준)
--   features    : 장식 플래그 { horn, crown, sparkle, glow }

export type AlpacaFeatures = {
	horn: boolean,
	crown: boolean,
	sparkle: boolean,
	glow: boolean,
}

export type AlpacaDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	currency: "Money" | "Robux",
	price: number,
	robuxPrice: number?,
	robuxProductId: number?,
	countInDex: boolean,
	careReward: number,
	woolValue: number,
	bodyColor: Color3,
	accentColor: Color3,
	scale: number,
	features: AlpacaFeatures,
	desc: string,
}

local function features(horn: boolean, crown: boolean, sparkle: boolean, glow: boolean): AlpacaFeatures
	return { horn = horn, crown = crown, sparkle = sparkle, glow = glow }
end

GameConfig.Alpacas = {
	{
		id = "grassland",
		displayName = "들풀 알파카",
		rarity = "Common",
		currency = "Money",
		price = 50,
		countInDex = true,
		careReward = 3,
		woolValue = 2,
		bodyColor = Color3.fromRGB(154, 200, 140),
		accentColor = Color3.fromRGB(110, 160, 100),
		scale = 0.92,
		features = features(false, false, false, false),
		desc = "농장의 첫 친구. 어디서든 잘 자라는 튼튼한 알파카.",
	},
	{
		id = "cotton",
		displayName = "솜털 알파카",
		rarity = "Common",
		currency = "Money",
		price = 250,
		countInDex = true,
		careReward = 6,
		woolValue = 6,
		bodyColor = Color3.fromRGB(242, 238, 226),
		accentColor = Color3.fromRGB(212, 205, 188),
		scale = 0.96,
		features = features(false, false, false, false),
		desc = "포근한 솜사탕 같은 털을 가진 알파카.",
	},
	{
		id = "meadow",
		displayName = "초원 알파카",
		rarity = "Uncommon",
		currency = "Money",
		price = 1000,
		countInDex = true,
		careReward = 12,
		woolValue = 18,
		bodyColor = Color3.fromRGB(128, 200, 178),
		accentColor = Color3.fromRGB(88, 158, 138),
		scale = 1.0,
		features = features(false, false, false, false),
		desc = "넓은 초원을 닮은 청량한 빛깔의 알파카.",
	},
	{
		id = "maple",
		displayName = "단풍 알파카",
		rarity = "Uncommon",
		currency = "Money",
		price = 4000,
		countInDex = true,
		careReward = 25,
		woolValue = 50,
		bodyColor = Color3.fromRGB(222, 120, 62),
		accentColor = Color3.fromRGB(170, 80, 40),
		scale = 1.02,
		features = features(true, false, false, false),
		desc = "가을 단풍처럼 따뜻한 색을 입은 알파카.",
	},
	{
		id = "snow",
		displayName = "눈송이 알파카",
		rarity = "Rare",
		currency = "Money",
		price = 15000,
		countInDex = true,
		careReward = 50,
		woolValue = 140,
		bodyColor = Color3.fromRGB(236, 245, 255),
		accentColor = Color3.fromRGB(182, 212, 236),
		scale = 1.05,
		features = features(true, false, true, false),
		desc = "겨울 첫눈처럼 새하얀, 차분한 알파카.",
	},
	{
		id = "golden",
		displayName = "황금 알파카",
		rarity = "Rare",
		currency = "Money",
		price = 50000,
		countInDex = true,
		careReward = 100,
		woolValue = 400,
		bodyColor = Color3.fromRGB(240, 200, 80),
		accentColor = Color3.fromRGB(200, 150, 40),
		scale = 1.08,
		features = features(true, true, true, false),
		desc = "햇살을 머금은 듯 반짝이는 귀한 알파카.",
	},
	{
		id = "rainbow",
		displayName = "무지개 알파카",
		rarity = "Epic",
		currency = "Money",
		price = 180000,
		countInDex = true,
		careReward = 200,
		woolValue = 1100,
		bodyColor = Color3.fromRGB(236, 130, 200),
		accentColor = Color3.fromRGB(140, 200, 240),
		scale = 1.12,
		features = features(true, true, true, false),
		desc = "일곱 빛깔이 어른거리는 환상적인 알파카.",
	},
	{
		id = "crystal",
		displayName = "수정 알파카",
		rarity = "Epic",
		currency = "Money",
		price = 600000,
		countInDex = true,
		careReward = 400,
		woolValue = 3000,
		bodyColor = Color3.fromRGB(150, 226, 236),
		accentColor = Color3.fromRGB(92, 182, 212),
		scale = 1.16,
		features = features(true, true, true, true),
		desc = "맑은 수정처럼 빛을 투과하는 신비한 알파카.",
	},
	{
		id = "galaxy",
		displayName = "은하 알파카",
		rarity = "Legendary",
		currency = "Money",
		price = 1500000,
		countInDex = true,
		careReward = 800,
		woolValue = 7000,
		bodyColor = Color3.fromRGB(92, 72, 172),
		accentColor = Color3.fromRGB(162, 122, 232),
		scale = 1.22,
		features = features(true, true, true, true),
		desc = "밤하늘의 은하를 등에 업은 전설적인 알파카.",
	},
	{
		id = "legend",
		displayName = "전설의 알파카",
		rarity = "Mythic",
		currency = "Money",
		price = 3000000,
		countInDex = true,
		careReward = 1500,
		woolValue = 16000,
		bodyColor = Color3.fromRGB(255, 232, 152),
		accentColor = Color3.fromRGB(255, 182, 90),
		scale = 1.3,
		features = features(true, true, true, true),
		desc = "농장주의 자부심. 모두가 꿈꾸는 궁극의 알파카.",
	},

	-- ───────── 로벅스 한정 (현재 비활성, 도감 미포함) ─────────
	{
		id = "unicorn",
		displayName = "유니콘파카",
		rarity = "Mythic",
		currency = "Robux",
		price = 0,
		robuxPrice = 499,
		robuxProductId = nil, -- 출시 시 GamePass/DevProduct id 연결
		countInDex = false,
		careReward = 1000,
		woolValue = 12000,
		bodyColor = Color3.fromRGB(255, 250, 255),
		accentColor = Color3.fromRGB(255, 170, 220),
		scale = 1.28,
		features = features(true, true, true, true),
		desc = "이마에 무지개 뿔이 돋은 로벅스 한정 알파카.",
	},
}

-- 빠른 조회를 위한 id → AlpacaDef 맵
GameConfig.AlpacasById = {} :: { [string]: AlpacaDef }
for _, a in ipairs(GameConfig.Alpacas) do
	GameConfig.AlpacasById[a.id] = a
end

-- 도감에 포함되는 종 수 (엔드게임 목표)
GameConfig.DexTotal = 0
for _, a in ipairs(GameConfig.Alpacas) do
	if a.countInDex then
		GameConfig.DexTotal += 1
	end
end

-- =====================================================================
-- 경제 / 슬롯
-- =====================================================================
GameConfig.Economy = {
	startingMoney = 300, -- 신규 플레이어 시작 머니
	startingSlots = 3, -- 시작 농장 슬롯 수
	maxSlots = 10, -- 한 농장 최대 알파카 수(=최대 슬롯). 그리드(slotCols*slotRows=12) 안이라 안전

	-- 전역 머니 배수: 케어 보상과 양털 수익 모두에 곱해집니다.
	-- "돈이 너무 안 벌린다" 대응으로 5배 상향. 더/덜 벌게 하려면 이 숫자만 바꾸면 됩니다.
	moneyMultiplier = 5,

	-- 되팔기(판매) 환급 비율: 먹이/악세사리/알파카를 원가의 이 비율만큼 돌려받는다.
	-- 예) 0.8 → 원가의 80% 환급. 0.5 면 절반만.
	sellRatio = 0.8,

	-- 먹이/악세사리 등 "추가 소비재"는 알파카가 최소 이 수만큼 있어야 구매 가능.
	-- (알파카 없이 돈을 다 써버려 수익원이 사라지는 막다른 길 방지)
	minAlpacasToShop = 1,

	-- N번째 슬롯을 여는 비용. slotCosts[i] = (startingSlots + i)번째 슬롯 비용.
	-- 예) startingSlots=3 이면 slotCosts[1] = 4번째 슬롯 비용.
	slotCosts = {
		5000, -- 4번째
		50000, -- 5번째
		200000, -- 6번째
		600000, -- 7번째
		1500000, -- 8번째
		3000000, -- 9번째
		6000000, -- 10번째
		12000000, -- 11번째
		25000000, -- 12번째
	},
}

-- 되팔기 환급액: 원가(price)에 sellRatio 를 곱해 내림한 정수. 음수/0 은 0 처리.
function GameConfig.sellPrice(price: number): number
	if not price or price <= 0 then
		return 0
	end
	return math.floor(price * GameConfig.Economy.sellRatio)
end

-- 슬롯 확장 비용 조회 헬퍼. 현재 슬롯 수(currentSlots)에서 한 칸 더 늘릴 때의 비용.
-- 더 늘릴 수 없으면 nil 반환.
function GameConfig.getNextSlotCost(currentSlots: number): number?
	if currentSlots >= GameConfig.Economy.maxSlots then
		return nil
	end
	local index = currentSlots - GameConfig.Economy.startingSlots + 1
	return GameConfig.Economy.slotCosts[index]
end

-- =====================================================================
-- 욕구 / 케어
-- =====================================================================
-- 욕구 3종(배고픔 Hunger / 털엉킴 Tangle / 더러움 Dirt)은 0~100.
-- riseTime 초에 걸쳐 0 → 100 으로 천천히 상승한다.
-- 욕구가 careThreshold 이상일 때만 해당 케어가 가능 → 욕구가 차오르는 속도가
-- 곧 자연스러운 쿨다운이 된다(무한 클릭 방지).
export type CareType = "feed" | "brush" | "bath"

GameConfig.Care = {
	riseTime = 300, -- 욕구가 0→100 까지 차오르는 시간(초). ≈5분
	tickInterval = 2, -- 욕구 갱신 주기(초)
	careThreshold = 20, -- 이 값 이상이어야 케어 가능 (≈60초 쿨다운)
	actionDebounce = 0.4, -- 같은 알파카 연속 케어 방지(초)
	proximity = 16, -- 케어 가능 최대 거리(studs)

	-- 케어 종류 → 대응 욕구 / 표시 정보
	types = {
		feed = { need = "Hunger", emoji = "🍃", label = "먹이주기", color = Color3.fromRGB(120, 195, 95) },
		brush = { need = "Tangle", emoji = "🪮", label = "빗어주기", color = Color3.fromRGB(110, 160, 240) },
		bath = { need = "Dirt", emoji = "🛁", label = "목욕시키기", color = Color3.fromRGB(95, 200, 220) },
	},

	-- 외형 변화 임계치 (이 값 이상이면 해당 상태가 외형에 보임)
	visualThreshold = {
		Hunger = 55, -- 배고픔 표시 (말풍선)
		Tangle = 50, -- 털 엉킴 표시 (거친 털 색/돌출)
		Dirt = 50, -- 더러움 표시 (얼룩)
	},

	-- 굶주림 사망 규칙 ───────────────────────────────────────────────
	-- 먹이를 주지 않은 채(=먹이주기 케어를 안 한 채) 시간이 지나면 알파카가 떠난다.
	-- "먹이를 준 마지막 시각"(모델 Fed 속성)을 기준으로 경과 시간을 잰다.
	-- ⚠ 접속 중(서버에 모델이 떠 있는 동안)에만 카운트된다. 퇴장하면 다시 스폰될 때
	--   Fed 가 현재시각으로 초기화되므로 오프라인 시간으로는 죽지 않는다(과한 패널티 방지).
	starveWarnTime = 600, -- 이 시간(초) 동안 안 먹이면 경고 알림 1회 (10분)
	starveDeathTime = 1200, -- 이 시간(초) 동안 안 먹이면 사망 (20분)
}

-- 행복도 계산: 100 - (Hunger + Tangle + Dirt)/3, 0~100 으로 클램프
function GameConfig.computeHappiness(hunger: number, tangle: number, dirt: number): number
	local avgNeed = (hunger + tangle + dirt) / 3
	return math.clamp(100 - avgNeed, 0, 100)
end

-- =====================================================================
-- 먹이 상점 (인벤토리형 먹이)
-- =====================================================================
-- 먹이는 "먹이 상점"에서 구매해 인벤토리에 쌓아두고, 그중 하나를 "사용 먹이"로
-- 선택한다. 화면 하단 [먹이주기] 버튼을 누르면 선택한 먹이가 1개 소비되며
-- 그 먹이의 효과(보상 배수·추가 정돈·양털 보너스)가 적용된다.
-- 인벤토리가 비면 자동으로 기본 먹이(grass, 무료)로 대체된다.
--
--  price      : 1개 구매 가격(게임머니). 0 = 기본 제공(무료·무한).
--  rewardMult : 먹이주기 케어 보상 배수 (기본 1.0)
--  extraClean : 먹이주기 시 털엉킴/더러움도 이만큼(0~100) 함께 감소
--  woolBonus  : 먹이를 줄 때 그 알파카의 양털(머니)에 즉시 적립되는 양(상한 적용)
export type FoodDef = {
	id: string,
	displayName: string,
	emoji: string,
	price: number,
	rewardMult: number,
	extraClean: number,
	woolBonus: number,
	desc: string,
}

GameConfig.Foods = {
	{
		id = "grass",
		displayName = "기본 풀",
		emoji = "🌿",
		price = 0,
		rewardMult = 1.0,
		extraClean = 0,
		woolBonus = 0,
		desc = "어디에나 자라는 기본 먹이. 공짜이며 항상 사용할 수 있어요.",
	},
	{
		id = "carrot",
		displayName = "아삭 당근",
		emoji = "🥕",
		price = 200,
		rewardMult = 1.5,
		extraClean = 0,
		woolBonus = 5,
		desc = "달콤한 당근. 케어 보상이 1.5배가 돼요.",
	},
	{
		id = "hay",
		displayName = "영양 건초",
		emoji = "🌾",
		price = 1200,
		rewardMult = 2.0,
		extraClean = 25,
		woolBonus = 40,
		desc = "든든한 건초. 보상 2배 + 털도 살짝 정돈돼요.",
	},
	{
		id = "premium",
		displayName = "프리미엄 사료",
		emoji = "🍱",
		price = 6000,
		rewardMult = 3.0,
		extraClean = 60,
		woolBonus = 250,
		desc = "고급 사료. 보상 3배 + 털·더러움 크게 정돈 + 양털 보너스.",
	},
	{
		id = "magic",
		displayName = "마법 사료",
		emoji = "✨",
		price = 30000,
		rewardMult = 5.0,
		extraClean = 100,
		woolBonus = 1500,
		desc = "전설의 사료. 보상 5배 + 모든 욕구 정돈 + 양털 듬뿍!",
	},
}

GameConfig.FoodsById = {} :: { [string]: FoodDef }
for _, f in ipairs(GameConfig.Foods) do
	GameConfig.FoodsById[f.id] = f
end

-- 인벤토리가 비었을 때 자동으로 쓰는 기본 먹이 id
GameConfig.DefaultFood = "grass"

-- =====================================================================
-- 악세사리 가게 (알파카 옷/장신구)
-- =====================================================================
-- 악세사리는 "악세사리 가게"에서 구매하면 보유 목록에 추가되고, 보유한 악세사리를
-- 골라 내 알파카에게 입힐 수 있다(알파카 1마리당 1개 착용). AlpacaSpawner 가 kind 에
-- 맞춰 머리/목/등에 파트를 붙인다.
--
--  kind   : 장착 형태 — "hat"|"tophat"|"bow"|"scarf"|"glasses"|"flower"|"crown"|"cape"
--  color  : 주 색상,  accent : 보조 색상(없으면 color 재사용)
export type AccessoryDef = {
	id: string,
	displayName: string,
	emoji: string,
	price: number,
	kind: string,
	color: Color3,
	accent: Color3?,
	desc: string,
}

GameConfig.Accessories = {
	{
		id = "strawhat",
		displayName = "밀짚모자",
		emoji = "👒",
		price = 300,
		kind = "hat",
		color = Color3.fromRGB(226, 196, 124),
		accent = Color3.fromRGB(176, 120, 70),
		desc = "농부 알파카의 필수템. 햇살 가득 밀짚모자.",
	},
	{
		id = "bow",
		displayName = "리본",
		emoji = "🎀",
		price = 400,
		kind = "bow",
		color = Color3.fromRGB(240, 120, 170),
		accent = Color3.fromRGB(210, 80, 140),
		desc = "머리에 콕 얹는 깜찍한 리본.",
	},
	{
		id = "scarf",
		displayName = "목도리",
		emoji = "🧣",
		price = 600,
		kind = "scarf",
		color = Color3.fromRGB(210, 80, 80),
		accent = Color3.fromRGB(245, 240, 235),
		desc = "포근한 겨울 목도리.",
	},
	{
		id = "glasses",
		displayName = "선글라스",
		emoji = "🕶️",
		price = 800,
		kind = "glasses",
		color = Color3.fromRGB(35, 35, 40),
		accent = Color3.fromRGB(90, 90, 100),
		desc = "한껏 멋부린 선글라스.",
	},
	{
		id = "flower",
		displayName = "꽃 화관",
		emoji = "🌸",
		price = 1000,
		kind = "flower",
		color = Color3.fromRGB(245, 140, 195),
		accent = Color3.fromRGB(255, 230, 120),
		desc = "들꽃을 엮어 만든 화관.",
	},
	{
		id = "tophat",
		displayName = "실크 모자",
		emoji = "🎩",
		price = 1500,
		kind = "tophat",
		color = Color3.fromRGB(28, 28, 34),
		accent = Color3.fromRGB(120, 90, 60),
		desc = "신사 알파카를 위한 고급 실크 모자.",
	},
	{
		id = "cape",
		displayName = "영웅 망토",
		emoji = "🦸",
		price = 2500,
		kind = "cape",
		color = Color3.fromRGB(120, 70, 200),
		accent = Color3.fromRGB(240, 220, 90),
		desc = "펄럭이는 영웅의 망토.",
	},
	{
		id = "crown",
		displayName = "황금 왕관",
		emoji = "👑",
		price = 5000,
		kind = "crown",
		color = Color3.fromRGB(255, 215, 80),
		accent = Color3.fromRGB(255, 120, 160),
		desc = "농장의 왕! 반짝이는 황금 왕관.",
	},
}

GameConfig.AccessoriesById = {} :: { [string]: AccessoryDef }
for _, a in ipairs(GameConfig.Accessories) do
	GameConfig.AccessoriesById[a.id] = a
end

-- =====================================================================
-- 양털 (패시브 수익)
-- =====================================================================
GameConfig.Wool = {
	cycle = 45, -- 양털 적립 주기(초) — 더 자주 쌓이도록 단축(기존 60)
	-- 행복도에 따른 양털 수익 배수: 행복 0 → minMultiplier, 행복 100 → 1.0
	minMultiplier = 0.5,
	-- 양털 수익 배수: 전역 머니 배수(Economy.moneyMultiplier)를 그대로 사용.
	-- (적립 속도와 수령액이 함께 커집니다. 돈을 더 벌게 하려면 Economy.moneyMultiplier 를 올리세요.)
	incomeMultiplier = GameConfig.Economy.moneyMultiplier,
	-- 알파카별 양털(머니) 누적 상한 = woolValue * capCycles (장시간 미수집 방지)
	-- incomeMultiplier 로 빨리 차므로 상한도 함께 상향(기존 120)
	capCycles = 240,
	autoCollect = false, -- true 면 적립 즉시 자동 머니화 (기본: 수집 버튼)
}

-- =====================================================================
-- 농장 / 맵
-- =====================================================================
GameConfig.Farm = {
	maxFarms = 8, -- 동시에 배정 가능한 개인 농장 구역 수 (= 서버 최대 인원 가정)
	plotSize = 60, -- 한 농장 구역 한 변 길이(studs)
	plotGap = 16, -- 농장 사이 간격(studs)
	fenceHeight = 6, -- 울타리 높이
	-- 슬롯 배치 그리드 (maxSlots 이상이어야 함): cols * rows >= maxSlots
	slotCols = 4,
	slotRows = 3,
}

-- =====================================================================
-- 리더보드 (총자산 순위)
-- =====================================================================
GameConfig.Leaderboard = {
	topCount = 10, -- 글로벌 순위표 표시 인원
	cacheSeconds = 60, -- 글로벌 순위 캐시 갱신 주기(초)
	submitInterval = 60, -- 내 총자산 제출 주기(초)
}

-- =====================================================================
-- 로벅스 (GamePass / DevProduct) — 현재 비활성, 구조만 준비
-- =====================================================================
-- 출시 시 id 를 채우고 enabled = true 로 바꾸면 동작합니다.
GameConfig.Monetization = {
	enabled = false, -- 전체 로벅스 결제 활성화 스위치 (출시 전 false)

	-- 수익 2배 게임패스
	incomeBoost = {
		gamePassId = 0, -- 실제 GamePass id (0 = 미연결)
		displayName = "황금 갈퀴 (수익 2배)",
		desc = "케어·양털 수익이 영구히 2배가 됩니다.",
		multiplier = 2,
		robuxPrice = 199,
	},
}

-- =====================================================================
-- 사운드 (효과음)
-- =====================================================================
-- 모두 로블록스에 "기본 내장"된 에셋(rbxasset://)이라 업로드/퍼블리시 없이 바로 재생됩니다.
-- → 친구와 함께 플레이해도 추가 설정 없이 소리가 납니다.
-- 더 멋진 소리로 바꾸려면 아래 경로를 카탈로그 사운드 id("rbxassetid://12345")로 교체하세요.
GameConfig.Sounds = {
	feed     = "rbxassetid://625712280",  -- 먹는 소리 '냠냠'(IsPublicDomain 검증됨 → 미공개/스튜디오/친구 플레이 모두 재생). 케어 시 알파카 위치에서 서버 재생
	eat      = "rbxassetid://625712280",  -- (구 키, 현재 미사용) feed 와 동일
	brush    = "rbxassetid://624706518",  -- 빗질 '스윽'(Whoosh, IsPublicDomain 검증됨 → 어느 게임에서나 재생)
	bath     = "rbxasset://sounds/impact_water.mp3",       -- 목욕(첨벙)
	buy      = "rbxasset://sounds/action_jump.mp3",        -- 알파카 구매
	wool     = "rbxasset://sounds/action_jump_land.mp3",   -- 양털 수집
	teleport = "rbxasset://sounds/action_jump.mp3",        -- 빠른 이동
	click    = "rbxasset://sounds/volume_slider.ogg",      -- UI 버튼 클릭
	error    = "rbxasset://sounds/ouch.ogg",               -- 실패/경고
	volume   = 0.55,
}

-- careType("feed"|"brush"|"bath") → 사운드 경로 (없으면 click)
function GameConfig.careSound(careType: string): string
	return (GameConfig.Sounds :: any)[careType] or GameConfig.Sounds.click
end

-- =====================================================================
-- 플레이어 케어 동작 애니메이션
-- =====================================================================
-- 로블록스 기본 R15 이모트 애니메이션 id(로블록스 소유 → 어느 게임에서나 로드 가능).
-- 클라이언트에서 pcall 로 안전하게 로드하고, 실패하면 살짝 점프로 대체합니다.
GameConfig.Animations = {
	feed  = "rbxassetid://507770453", -- Point (먹이 내미는 느낌)
	brush = "rbxassetid://507770239", -- Wave  (빗질하듯 손 움직임)
	bath  = "rbxassetid://507770677", -- Cheer (신나게)
}

-- careType → 애니메이션 id (없으면 wave)
function GameConfig.careAnim(careType: string): string
	return (GameConfig.Animations :: any)[careType] or GameConfig.Animations.brush
end

-- =====================================================================
-- 알파카 배회 움직임(자연스러움) 튜닝
-- =====================================================================
-- AlpacaAI 가 사용. 값이 클수록 빠르고 활발해집니다.
GameConfig.Wander = {
	moveSpeed   = 5,    -- 평균 이동 속도(studs/s)
	accel       = 9,    -- 가/감속(부드러운 출발·정지). 클수록 즉각적
	turnRate    = 7,    -- 방향 전환 부드러움(클수록 빨리 돌아봄)
	arriveDist  = 2.0,  -- 도착 판정 수평 거리
	pauseChance = 0.45, -- 목적지 도달 시 잠깐 풀 뜯으며 쉴 확률
	pauseMin    = 1.2,  -- 최소 휴식(초)
	pauseMax    = 3.5,  -- 최대 휴식(초)
	bobHeight   = 0.12, -- 걸을 때 위아래 미세한 들썩임 높이(studs) — 과하면 둥둥 떠 보임
	bobSpeed    = 8,    -- 걸음 빈도(다리 스윙 주파수와 공유)
	swayAngle   = 0.0,  -- (사용 안 함) 좌우 몸통 roll — 0 으로 두어 '춤추는' 느낌 제거
	legSwing    = 0.55, -- 다리 앞뒤 스윙 최대 각(라디안 ≈ 31°). 걸을 때 다리가 움직이는 핵심 값
}

-- =====================================================================
-- 케어 시 알파카 반응 (깡총 + 하트)
-- =====================================================================
GameConfig.CareReaction = {
	duration   = 1.1,  -- 반응 지속(초)
	hopHeight  = 1.6,  -- 깡총 높이(studs)
	hopCount   = 2,    -- 깡총 횟수
	facePlayer = true, -- 케어해준 사람을 바라봄
}

-- =====================================================================
-- 배경 음악 (BGM)
-- =====================================================================
-- ⚠️ 로블록스는 '내장(rbxasset)' 음악 트랙을 제공하지 않습니다. 아래 tracks 의
--    id 는 예시이며, 친구와 함께 확실히 들으려면 "내가 소유했거나 Roblox 가 만든"
--    오디오 Asset ID 로 교체하세요.
--    교체 방법: Studio 상단 [보기]→[툴박스] 또는 크리에이터 스토어 → Audio(오디오)
--    에서 마음에 드는 곡을 찾아 우클릭→"에셋 ID 복사", "rbxassetid://<숫자>" 형태로
--    아래 tracks 목록에 넣으면 됩니다. (여러 개 넣으면 순서대로 반복 재생)
GameConfig.Music = {
	enabled = true,  -- 접속 시 BGM 자동 켜짐 여부
	volume  = 0.25,  -- 배경음 볼륨(0~1) — 효과음보다 작게
	tracks  = {
		"rbxassetid://1837879082", -- (예시) 마음에 드는 곡 id 로 교체하세요
	},
}

return GameConfig
