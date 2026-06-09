#!/bin/bash
# RaiserOS Builder — главный скрипт
# ПК:  bash build.sh        → запросит ссылку интерактивно
# Бот: bash build.sh <URL>  → получает URL из Actions

set -euo pipefail
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WORK_DIR

source "$WORK_DIR/config.env"
source "$WORK_DIR/functions.sh"
export PATH="$WORK_DIR/bin/Linux/x86_64:$PATH"
chmod -R 755 "$WORK_DIR/bin/Linux/x86_64/" 2>/dev/null || true

ROM_INPUT="${1:-}"
if [[ -z "$ROM_INPUT" ]]; then
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║      RaiserOS Builder  —  PC Mode        ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "Введи прямую ссылку на ColorOS OTA .zip"
  echo "или путь к локальному файлу:"
  echo -n "  → "
  read -r ROM_INPUT
  [[ -z "$ROM_INPUT" ]] && error "Ссылка не указана."
fi

PARTS="system system_ext product vendor odm vendor_dlkm system_dlkm odm_dlkm"
check unzip aria2c curl zip java python3 zstd bc

step "Загружаю прошивку"
mkdir -p "$WORK_DIR/build/base/images/config"
if [[ "$ROM_INPUT" =~ ^https?:// ]]; then
  ROM_FILE="$WORK_DIR/build/base/$(basename "$ROM_INPUT" | sed 's/?.*//')"
  download_rom "$ROM_INPUT" "$ROM_FILE"
else
  [[ -f "$ROM_INPUT" ]] || error "Файл не найден: $ROM_INPUT"
  ROM_FILE="$ROM_INPUT"
fi

step "Проверка архива"
unzip -l "$ROM_FILE" | grep -q "payload.bin" || error "Нет payload.bin в архиве"
unzip "$ROM_FILE" payload.bin -d "$WORK_DIR/build/base" &>/dev/null || error "Ошибка извлечения payload.bin"

step "Дамп партиций"
payload-dumper-go -o "$WORK_DIR/build/base/images/" "$WORK_DIR/build/base/payload.bin" &>/dev/null || error "payload-dumper-go упал"
rm -f "$WORK_DIR/build/base/payload.bin"

step "Извлечение партиций"
for p in $PARTS; do
  img="$WORK_DIR/build/base/images/${p}.img"
  [[ -f "$img" ]] || { warn "Нет ${p}.img — пропуск"; continue; }
  extract_partition "$img" "$WORK_DIR/build/base/images"
done

step "Читаю метаданные ROM"
fetch_rom_info "$WORK_DIR/build/base/images/system"

step "Применяю RaiserOS моды"
bash "$WORK_DIR/patches/apply_mods.sh" "$WORK_DIR/build/base/images" "$WORK_DIR/config.env"

step "Удаляю filesystem verity"
for p in $PARTS; do remove_fsv "$WORK_DIR/build/base/images/$p"; done

step "Перепаковка партиций"
for p in $PARTS; do
  [[ -d "$WORK_DIR/build/base/images/$p" ]] && repack_partition "$p" "$WORK_DIR/build/base/images"
done

step "Собираю flashable ZIP"
bash "$WORK_DIR/packROM.sh"

step "Загружаю в Releases"
bash "$WORK_DIR/uploadROM.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       RaiserOS build готов! 🎉           ║"
echo "╚══════════════════════════════════════════╝"
