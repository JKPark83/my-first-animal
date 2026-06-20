# 로블록스 게임 게시 & 친구(서주)와 함께 플레이하기

> **나의 첫 알파카 농장**을 게시하고 친구와 함께 플레이하는 최신(2026-06 기준) 가이드입니다.
> ⚠️ 2025~2026년에 로블록스 공개 정책이 크게 바뀌었습니다. 예전 방식("잠깐 Public 누르면 끝")은
> 더 이상 통하지 않습니다. 아래 순서대로 따라 하세요.

---

## ❗ 먼저 알아둘 것 (2025~2026 정책 변경 핵심)

1. **콘텐츠 성숙도 설문(Maturity & Compliance)이 필수**가 되었습니다.
   - 2025-09-30부터, 설문을 작성하지 않은 게임은 **본인 외 누구도 플레이/검색 불가**(사실상 잠김).
   - 작성은 5분이면 끝납니다. (아래 4단계)
2. **완전 공개(Public)에는 "게시 자격"이 필요**합니다 (2025-12-17부터).
   - 본인 **ID 인증** **또는** 2025-01-01 이후 **실제 돈/기프트카드 결제 이력** 중 하나.
   - 자격 확인: https://create.roblox.com/settings/eligibility/public-publish
3. **16세 미만(키즈/Select)이 "검색해서" 들어오게 하려면 훨씬 까다롭습니다.**
   - ID 인증 + 2단계 인증 + Roblox Plus(2개월) 또는 1,000 Robux + 평가(60일 500명 고참여)…
   - 신규 게임이 어린 친구에게 "검색 노출"까지 가는 건 당장은 현실적으로 어렵습니다.
   - 👉 그래서 **서주만 들어오게 하려면 아래 "방법 A(친구 초대)"가 가장 빠릅니다.**

---

## 1단계 — 사전 준비

1. **빌드** (이미 완료되어 있으면 생략)
   ```
   rojo build -o game.rbxlx
   ```
2. **Studio 에서 열기** — `game.rbxlx` 더블클릭, 또는 **File → Open from File**.
3. **로그인 확인** — Studio 우측 상단에 내 아이디가 보이는지 확인.

---

## 2단계 — 처음 게시하기 (비공개로 생성됨)

1. 상단 메뉴 **File → Publish to Roblox** (Mac 단축키 `⌥P`. 처음엔 메뉴 클릭이 더 안정적).
   - (기존 게임에 장소를 덮어쓸 때만 *Publish to Roblox As…* 를 씁니다. 새 게임은 그냥 *Publish to Roblox*.)
2. 창이 뜨면 입력:
   - **Name (이름):** `나의 첫 알파카 농장`
   - **Description (설명):** `알파카를 키우고 농장을 가꾸는 귀여운 게임!`
   - **Creator:** 본인 계정 (또는 그룹)
   - **Devices:** 기본값 유지 (PC/모바일 등)
3. **Create** 클릭 → 클라우드에 저장됩니다.
   - 이때 게임은 **자동으로 비공개(Private)** 입니다. 아직 아무도 못 들어옵니다.

> 이후 코드/맵을 고치면 매번 **File → Publish to Roblox** 로 다시 게시해야 반영됩니다. (저장만으론 반영 안 됨)

---

## 3단계 — 데이터 저장(DataStore) 켜기

이 게임은 농장 데이터를 저장합니다. **실제 게시 서버에선 자동 동작**하지만, Studio 테스트에서도 보려면:

1. **Home 탭 → Game Settings → Security**
2. **Enable Studio Access to API Services** 체크 → **Save**

---

## 4단계 — 콘텐츠 성숙도 설문 작성 (필수, 5분)

> 이걸 안 하면 친구에게 공개해도 **아무도 못 들어옵니다.**

1. 브라우저에서 https://create.roblox.com 접속 → 로그인.
2. **Creations** 에서 방금 만든 게임 클릭.
3. 왼쪽 메뉴 **Audience → Maturity & Compliance**.
4. 콘텐츠 관련 질문(폭력/공포 등 거의 "없음")에 답하고 **Save and Continue**.
   - 이 게임은 알파카 케어 게임이라 대부분 "없음"으로 **Minimal(최소)** 등급이 나옵니다.

---

## 5단계 — 친구를 들어오게 하기 (목표에 맞게 택1)

### ✅ 방법 A — 서주만 들어오게 (가장 빠르고 추천)

게임 접근을 **Friends(친구)** 로 설정하면, 내 로블록스 친구는 링크로 들어올 수 있고
검색에는 안 뜹니다. (완전 공개의 무거운 자격 조건을 피할 수 있어 가장 간단)

1. 먼저 **로블록스에서 서주와 친구 맺기** — 서로 Add Friend 수락.
2. **Studio: Home 탭 → Game Settings → Permissions(권한)** →
   **Playability** 를 **Friends** 로 변경 → **Save**.
   - (또는 브라우저 create.roblox.com → 게임 → **Configure → Settings → Audience** 에서도 가능. 두 곳은 연동됩니다.)
3. 게임 페이지 URL 을 서주에게 보내면 **Play** 로 입장 가능.

> 특정 1명만 정밀하게 넣고 싶다면: Studio 우측 상단 **Collaborate** → 서주 username 추가 →
> 권한 **Play** 로 지정하는 방법도 있습니다(게임은 계속 비공개 유지).

### 🌐 방법 B — 누구나 검색/플레이 (완전 공개)

1. 4단계 설문을 **반드시** 먼저 끝낼 것.
2. **게시 자격** 충족: 본인 ID 인증 **또는** 2025년 이후 결제 이력.
   - 확인: https://create.roblox.com/settings/eligibility/public-publish
3. **Game Settings → Permissions → Playability → Public** → Save.
   - 또는 create.roblox.com → 게임 → Configure → Settings → **Audience → Public**.
4. 연령 확인(얼굴/전화/ID) 요청이 나오면 진행.

> ⚠️ 어린(16세 미만) 친구가 **검색으로** 찾아 들어오게 하려면 위 "먼저 알아둘 것 3번"의
> 추가 조건들이 필요합니다. 그냥 같이 놀 목적이면 **방법 A** 를 권장합니다.

---

## 6단계 — 같은 서버에서 만나기

1. 한 명이 먼저 게임에 입장.
2. 다른 한 명이 로블록스 앱에서 먼저 들어간 친구 **프로필 → Join Game(게임 참가)**.
3. 이 게임은 **1인 1농장** — 같은 서버라도 각자 농장을 배정받아 서로 구경/채팅하며 즐깁니다.

---

## 7단계 — Robux 결제 안내

게임 내 Robux 결제는 **비활성 상태**(설정만 준비, 실제 판매 항목 없음). **무료 플레이**, PC/모바일 모두 지원.

---

## 문제 해결 FAQ

| 문제 | 해결 |
|------|------|
| 공개했는데 아무도 못 들어와요 | **4단계 성숙도 설문**을 안 했을 가능성이 가장 큽니다. 먼저 작성하세요. |
| Public 으로 못 바꿔요 | **게시 자격**(ID 인증 또는 결제 이력) 미충족. https://create.roblox.com/settings/eligibility/public-publish 확인. |
| 서주가 못 들어와요(비공개) | 비공개 게임은 친구도 못 들어옵니다. **방법 A(Friends 접근 또는 Playtester)** 로 바꾸세요. |
| 데이터가 저장 안 돼요 | Studio 테스트면 **3단계 API 서비스 허용** 확인. |
| 수정이 반영 안 돼요 | **File → Publish to Roblox** 로 다시 게시했는지 확인. |
| Publish 메뉴가 비활성 | Studio 우측 상단 **로그인** 확인. |

---

## 빠른 체크리스트

- [ ] `rojo build -o game.rbxlx` 빌드
- [ ] Studio 에서 `game.rbxlx` 열기 + 로그인 확인
- [ ] **File → Publish to Roblox** 로 첫 게시 (이름/설명 입력 → Create) — 비공개로 생성됨
- [ ] **Game Settings → Security → Enable Studio Access to API Services** (테스트용)
- [ ] **create.roblox.com → 게임 → Audience → Maturity & Compliance 설문 작성** ⚠️ 필수
- [ ] 목표 선택: **방법 A(Friends, 추천)** 또는 **방법 B(Public, 자격 필요)**
- [ ] 서주와 로블록스 친구 맺기 + 게임 URL 공유
- [ ] 한 명 먼저 입장 → 다른 한 명이 프로필 **Join Game** 으로 같은 서버 입장

---

> 정책은 자주 바뀝니다. 최신 자격/요건은 로그인 후
> https://create.roblox.com/settings/eligibility/public-publish 와
> 공식 문서 https://create.roblox.com/docs 에서 확인하세요.
