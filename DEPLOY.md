# 🚀 한 줄 자동 배포 (Open Cloud)

Roblox Studio 를 열지 않고 **터미널에서 `./deploy.sh` 한 번**으로 최신 코드를 라이브 게임에 게시합니다.

> 전제: 게임을 **최소 1회는 Studio 로 게시**해 둔 상태여야 합니다 (Place 가 이미 존재해야 함).
> 아직 첫 게시 전이라면 먼저 [`PUBLISH.md`](./PUBLISH.md) 를 따라 한 번 게시하세요.

---

## 1. 한 번만 설정하기

```bash
cp .env.example .env       # 템플릿 복사
# .env 를 열어 값 3개를 채운다 (아래 '값 구하는 법')
```

`.env` 에는 비밀키가 들어 있어 **`.gitignore`에 등록되어 있으므로 커밋에서 제외됩니다.** 절대 공유하지 마세요.

## 2. 배포

```bash
./deploy.sh
```

코드(`src/`)를 빌드해서 라이브 게임을 덮어씁니다. 끝나면 공유용 URL 이 출력됩니다.

---

## 값 3개 구하는 법

### ① `ROBLOX_API_KEY` — Open Cloud API 키
1. [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials) 접속
2. **Create API Key**
3. 설정:
   - **Access Permissions**: `universe-places` 추가 → 우리 게임(Universe) 선택 → **Write** 체크
   - **Security → IP allowlist**: 집 IP 를 넣거나, 테스트용으로 `0.0.0.0/0` (모든 IP 허용)
   - **Expiration**: 원하는 만료일
4. 생성된 키 문자열을 복사해 `.env` 의 `ROBLOX_API_KEY=` 뒤에 붙여넣기

### ② `ROBLOX_UNIVERSE_ID` — 게임(Experience) ID
- Creator Hub > **Creations** > 해당 게임 카드의 **⋯** 메뉴 > **Copy Universe ID**

### ③ `ROBLOX_PLACE_ID` — Place ID
- 게임 페이지 URL 의 숫자: `roblox.com/games/`**`<이 숫자>`**`/...`

---

## 자주 발생하는 오류

| 메시지 | 해결 |
|--------|------|
| `.env 파일이 없습니다` | `cp .env.example .env` 후 값 채우기 |
| `401 / Unauthorized` | API 키 권한에 `universe-places:write` 와 **해당 Universe** 가 포함됐는지 확인 |
| `403 / IP not allowed` | API 키의 **IP allowlist** 에 현재 IP 추가 (또는 `0.0.0.0/0`) |
| `404 / not found` | `ROBLOX_UNIVERSE_ID` / `ROBLOX_PLACE_ID` 숫자 확인 |

---

## 참고: Studio GUI 로 배포하던 방식과의 차이

| | Studio 게시 | `./deploy.sh` |
|---|---|---|
| Studio 실행 필요 | ✅ | ❌ (불필요) |
| 명령 | 메뉴 클릭 | 터미널 한 줄 |
| 자동화(CI) | 어려움 | 쉬움 |
| 최초 게시 | **가능** (이걸로 Place 생성) | 불가 (기존 Place 에 업로드만) |

→ **첫 게시는 Studio**로, 이후 업데이트는 `./deploy.sh`로 하는 방식을 추천합니다.
