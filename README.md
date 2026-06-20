# 알파카 농장 (Alpaca Farm)

빈 농장에서 **300$** 로 시작해 **10종 알파카(50$~300만$)** 를 사서 케어(먹이주기·빗어주기·목욕시키기)하고,
양털 패시브 수익으로 돈을 모아 **10종 도감 완성** 을 노리는 멀티플레이 케어/타이쿤 로블록스 게임.

---

## 실행 방법

### 준비

```bash
# Rojo 설치 여부 확인
rojo --version
```

Rojo 가 없으면 [rojo.space](https://rojo.space/) 에서 설치하고,
Roblox Studio 에는 **Rojo 플러그인** 을 마켓플레이스에서 설치해 두세요.

### 개발 모드 (라이브 동기화)

```bash
rojo serve
```

실행 후 Roblox Studio 의 Rojo 패널에서 **Connect** 를 누르면 파일 변경이 실시간으로 반영됩니다.

### 빌드 후 열기

```bash
rojo build -o game.rbxlx
```

생성된 `game.rbxlx` 를 Roblox Studio 에서 열어 플레이 테스트를 할 수 있습니다.

### 주의 사항

- **DataStore / 로벅스 기능**은 게시(Publish)된 경험에서만 완전히 동작합니다.
- Studio 에서 DataStore 를 테스트하려면 *게임 설정 → 보안 → "Enable Studio Access to API Services"* 를 켜세요.
- `GameConfig.Monetization.enabled` 가 기본 `false` 이므로 GamePass/DevProduct 는 실제 퍼블리시 후 ID 를 채우고 `true` 로 바꿔야 합니다.

---

## 폴더 구조

```
src/
├── ReplicatedStorage/
│   ├── GameConfig.luau          -- 알파카 정의·경제·케어·양털·슬롯 등 전체 밸런스 수치
│   └── Remotes.luau             -- RemoteEvent / RemoteFunction 팩토리 (이름 단일 관리)
│
├── ServerScriptService/
│   ├── Main.server.luau         -- 모든 서비스 init() 호출, 플레이어 입퇴장 처리
│   ├── DataManager.luau         -- DataStore 영구 저장·로드, 머니/슬롯/알파카/도감 상태 관리
│   ├── FarmBuilder.luau         -- 로비·개인 농장·울타리·가게 파츠를 코드로 절차적 빌드
│   ├── AlpacaSpawner.luau       -- 블록형 알파카 모델 생성, 등급별 색상·크기·장식 적용
│   ├── FarmService.luau         -- 농장 슬롯 배치, 알파카 모델 생성/제거 총괄 (글루 레이어)
│   ├── AlpacaShopService.luau   -- 알파카 구매·슬롯 확장 요청 처리 (서버 권한 검증)
│   ├── CareService.luau         -- 케어 요청 처리, 욕구 틱 루프, 행복도 계산, 케어 보상
│   ├── WoolService.luau         -- 60초 주기 양털 누적, 수집 요청 처리, 수익 부스트 적용
│   ├── CollectionService.luau   -- 도감 등록·조회 처리 (DataManager.markDex 래퍼)
│   ├── AlpacaAI.luau            -- 농장 내 알파카 배회·홈포지션 복귀 행동
│   ├── LeaderboardService.luau  -- OrderedDataStore 기반 글로벌 순위 집계·캐싱·브로드캐스트
│   └── GamePassService.luau     -- GamePass/Developer Product 구매 처리, 수익 부스트 적용
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        ├── UIController.client.luau  -- 상점 UI·HUD·도감·리더보드 화면 렌더링 및 입력 처리
        ├── CareController.client.luau -- 알파카 근접 감지, 하단 케어 버튼·양털 수집 버튼 제어
        └── AlpacaHud.client.luau     -- 알파카 머리 위 욕구 게이지(BillboardGui) 표시
```

---

## 게임플레이 요약

| 단계 | 내용 |
|------|------|
| 1. 입장 | 개인 농장 구역에 스폰, 300$ 지급 |
| 2. 구매 | 알파카 가게 패드를 밟으면 상점 UI 오픈 → 보유금 한도 내 구매 |
| 3. 케어 | 알파카 근처로 이동 → 하단 버튼 3개 활성화(먹이주기·빗어주기·목욕시키기) → 케어 시 현금 보상 |
| 4. 양털 | 알파카가 60초마다 양털 누적 → 수동 수집 또는 전체 수집 버튼으로 판매 |
| 5. 확장 | 돈을 모아 슬롯 확장 구매(최대 12칸), 상위 알파카 구매 |
| 6. 도감 | 10종을 최초 소유하면 도감 등록 → 전체 완성이 엔드게임 목표 |
| 7. 경쟁 | 순자산(머니+알파카+양털) 기준 글로벌 리더보드 상위권 도전 |

---

## 알파카 등급 & 경제

| # | 등급 | 가격 | 케어 보상 | 양털 / 60초 |
|---|------|-----:|----------:|------------:|
| 1 | 들풀 | 50$ | 3$ | 2$ |
| 2 | 솜털 | 250$ | 6$ | 6$ |
| 3 | 초원 | 1,000$ | 12$ | 18$ |
| 4 | 단풍 | 4,000$ | 25$ | 50$ |
| 5 | 눈송이 | 15,000$ | 50$ | 140$ |
| 6 | 황금 | 50,000$ | 100$ | 400$ |
| 7 | 무지개 | 180,000$ | 200$ | 1,100$ |
| 8 | 수정 | 600,000$ | 400$ | 3,000$ |
| 9 | 은하 | 1,500,000$ | 800$ | 7,000$ |
| 10 | 전설 | 3,000,000$ | 1,500$ | 16,000$ |

- 욕구(배고픔·털엉킴·더러움)는 약 5분에 걸쳐 0→100으로 상승. 임계치(20) 이상일 때만 케어 가능.
- 행복도가 낮으면 양털 수익이 최대 50% 감소.

---

## 밸런스 튜닝

모든 수치(알파카 정의·가격·케어 보상·양털 주기·욕구 속도·슬롯 비용·리더보드·로벅스)는
**`src/ReplicatedStorage/GameConfig.luau` 한 곳** 에서 관리합니다.
서버/클라 양쪽이 동일한 파일을 참조하므로 값을 바꾸면 전체에 즉시 반영됩니다.

---

## 로벅스 프리미엄

현재 `GameConfig.Monetization.enabled = false` 로 비활성화되어 있습니다.
게임을 퍼블리시한 뒤 아래 절차를 따르세요.

1. Roblox 개발자 대시보드에서 **GamePass** 와 **Developer Product** ID 를 발급받는다.
2. `GameConfig.luau` 의 `gamePassId`, `robuxProductId` 필드에 ID 를 채운다.
3. `GameConfig.Monetization.enabled = true` 로 변경한다.

현재 정의된 프리미엄 항목은 **황금 갈퀴 (수익 2배)** GamePass (robuxPrice: 199 Robux)입니다.
