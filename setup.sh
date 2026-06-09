#!/bin/bash
set -euo pipefail
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$WORK_DIR/bin/Linux/x86_64"
mkdir -p "$BIN"

log() { echo "[setup] $*"; }

log "Обновляю пакеты..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  unzip zip curl aria2 p7zip-full default-jdk \
  python3 python3-pip zstd bc xmlstarlet \
  lz4 erofs-utils e2fsprogs xxd apktool \
  rclone git

log "Python зависимости..."
pip3 install --quiet --break-system-packages protobuf brotli docopt

log "payload-dumper-go..."
if ! command -v payload-dumper-go &>/dev/null; then
  VER="1.2.2"
  URL="https://github.com/ssut/payload-dumper-go/releases/download/${VER}/payload-dumper-go_${VER}_linux_amd64.tar.gz"
  curl -fsSL "$URL" | tar -xz -C "$BIN" payload-dumper-go
  chmod +x "$BIN/payload-dumper-go"
  log "payload-dumper-go установлен"
fi

# Заглушки для python-скриптов если не скопированы вручную
for s in fspatch.py contextpatch.py ext4_extract.py; do
  [[ -f "$WORK_DIR/bin/$s" ]] || {
    log "STUB: $s — замени реальным скриптом из NothingsVN/oplus-toolbuild"
    printf '#!/usr/bin/env python3\nimport sys\nprint("[STUB] %s — replace me!")\nsys.exit(0)\n' "$s" \
      > "$WORK_DIR/bin/$s"
    chmod +x "$WORK_DIR/bin/$s"
  }
done

log "Готово! Запусти: bash build.sh"
