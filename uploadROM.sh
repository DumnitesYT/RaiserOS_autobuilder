#!/bin/bash
# RaiserOS — загрузка в GitHub Releases

set -euo pipefail
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WORK_DIR/config.env"
source "$WORK_DIR/functions.sh"

ZIP="${FINAL_ZIP:-$(ls -t "$WORK_DIR/build/"*.zip 2>/dev/null | head -1)}"
[[ -f "$ZIP" ]] || error "ZIP не найден. Запусти packROM.sh"
ZIP_NAME=$(basename "$ZIP")
log "Загружаю: $ZIP_NAME"

if [[ "$UPLOAD_TO_RELEASES" == "true" ]]; then
  step "Загружаю в GitHub Releases"
  TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
  [[ -z "$TOKEN" ]] && error "GH_TOKEN не задан"
  [[ -z "$REPO"  ]] && error "GH_REPO не задан (формат: owner/repo)"

  TAG="${ROM_BRAND}-${ROM_DEVICE:-device}-${ROM_BUILD_DATE:-$(date +%Y%m%d)}"
  RNAME="${ROM_BRAND} ${ROM_DEVICE:-device} ${ROM_VERSION:-unknown}"

  REL=$(curl -fsSL -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$RNAME\",\"body\":\"Automated RaiserOS build\",\"draft\":false}" \
    2>/dev/null || true)

  UP_URL=$(echo "$REL" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get(\'upload_url\',-\'\'))" 2>/dev/null \
    | sed "s/{?name,label}//")

  if [[ -z "$UP_URL" ]]; then
    UP_URL=$(curl -fsSL \
      -H "Authorization: Bearer $TOKEN" \
      "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get(\'upload_url\',-\'\'))" \
      | sed "s/{?name,label}//")
  fi

  [[ -z "$UP_URL" ]] && error "Не удалось получить upload URL"

  curl -fsSL -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/zip" \
    "${UP_URL}?name=${ZIP_NAME}" \
    --data-binary "@$ZIP" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print(\'Download URL:\', r.get(\'browser_download_url\',\'?\'))"

  log "Загружено в Releases ✓"
fi

if [[ "$UPLOAD_TO_RCLONE" == "true" ]]; then
  step "rclone → ${RCLONE_REMOTE}:${RCLONE_PATH}"
  command -v rclone &>/dev/null || error "rclone не установлен"
  rclone copy "$ZIP" "${RCLONE_REMOTE}:${RCLONE_PATH}/" --progress || error "rclone failed"
  log "rclone загрузка завершена ✓"
fi

log "Всё загружено ✓"
