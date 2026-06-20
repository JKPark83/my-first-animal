#!/usr/bin/env bash
#
# 🦙 나의 첫 알파카 농장 — 로블록스 자동 배포 스크립트
#
# Roblox Studio 를 열 필요 없이, 터미널 한 줄로 최신 코드를 라이브 게임에 게시합니다.
# (Rojo + Open Cloud API 사용)
#
#   사용법:  ./deploy.sh
#
# 처음이라면 README 대신 DEPLOY.md 를 먼저 읽어주세요.

set -euo pipefail

# --- 스크립트 위치 = 프로젝트 루트로 이동 ----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- .env 로드 -------------------------------------------------------------
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  echo "❌ .env 파일이 없습니다."
  echo "   먼저 템플릿을 복사하고 값을 채워주세요:"
  echo "     cp .env.example .env"
  exit 1
fi

# --- rojo 설치 확인 --------------------------------------------------------
if ! command -v rojo >/dev/null 2>&1; then
  echo "❌ rojo 가 설치되어 있지 않습니다.  (예: brew install rojo)"
  exit 1
fi

# --- 필수 값 확인 ----------------------------------------------------------
missing=()
[ -z "${ROBLOX_API_KEY:-}" ]     && missing+=("ROBLOX_API_KEY")
[ -z "${ROBLOX_UNIVERSE_ID:-}" ] && missing+=("ROBLOX_UNIVERSE_ID")
[ -z "${ROBLOX_PLACE_ID:-}" ]    && missing+=("ROBLOX_PLACE_ID")

if [ ${#missing[@]} -gt 0 ]; then
  echo "❌ .env 에 다음 값이 비어 있습니다: ${missing[*]}"
  echo "   DEPLOY.md 의 '값 3개 구하는 법' 을 참고해 채워주세요."
  exit 1
fi

# --- 배포 ------------------------------------------------------------------
echo "🦙 알파카 농장 배포 시작..."
echo "   Universe: ${ROBLOX_UNIVERSE_ID}   Place: ${ROBLOX_PLACE_ID}"
echo "   (Rojo 가 src/ 코드를 빌드해 라이브 게임을 덮어씁니다)"
echo ""

rojo upload \
  --api_key "${ROBLOX_API_KEY}" \
  --universe_id "${ROBLOX_UNIVERSE_ID}" \
  --asset_id "${ROBLOX_PLACE_ID}"

echo ""
echo "✅ 배포 완료! 변경 사항이 라이브 서버에 반영되었습니다."
echo "   친구에게 공유:  https://www.roblox.com/games/${ROBLOX_PLACE_ID}"
echo "   (게임이 Public 상태여야 친구가 들어올 수 있어요)"
