#!/bin/bash
# RaiserOS — собираем flashable ZIP

set -euo pipefail
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WORK_DIR/config.env"
source "$WORK_DIR/functions.sh"

IMAGES="$WORK_DIR/build/base/images"
PACK="$WORK_DIR/build/pack"
PARTS="system system_ext product vendor odm vendor_dlkm system_dlkm odm_dlkm"

[[ -z "$ROM_DEVICE" ]]     && ROM_DEVICE="device"
[[ -z "$ROM_BUILD_DATE" ]] && ROM_BUILD_DATE="$(date +%Y%m%d)"
[[ -z "$ROM_VERSION" ]]    && ROM_VERSION="unknown"

ZIP_NAME="${ROM_BRAND}_${ROM_DEVICE}_${ROM_VERSION}_${ROM_BUILD_DATE}.zip"
ZIP_OUT="$WORK_DIR/build/$ZIP_NAME"
export FINAL_ZIP="$ZIP_OUT"

step "Пакуем: $ZIP_NAME"
rm -rf "$PACK"
mkdir -p "$PACK/images" "$PACK/META-INF/com/google/android"

for p in $PARTS; do
  img="$IMAGES/${p}.img"
  [[ -f "$img" ]] && cp "$img" "$PACK/images/" && log "Добавлен: ${p}.img" || warn "Нет: ${p}.img"
done

cat > "$PACK/META-INF/com/google/android/updater-script" << USCRIPT
ui_print("RaiserOS Mod — flashing...");
USCRIPT

cat > "$PACK/META-INF/com/google/android/update-binary" << UBIN
#!/sbin/sh
OUTFD=/proc/self/fd/\$2
ZIPFILE="\$3"
ui_print() { echo "ui_print \$1" > \$OUTFD; echo "ui_print" > \$OUTFD; }
ui_print "RaiserOS — installing partitions"
for img in system system_ext product vendor odm vendor_dlkm system_dlkm odm_dlkm; do
  unzip -o "\$ZIPFILE" "images/\${img}.img" -d /tmp/raiser/ 2>/dev/null || continue
  t="/dev/block/by-name/\$img"
  [ -b "\$t" ] || t="/dev/block/bootdevice/by-name/\$img"
  [ -b "\$t" ] || { ui_print "Skip: \$img"; continue; }
  ui_print "Flash: \$img"
  dd if="/tmp/raiser/images/\${img}.img" of="\$t" bs=4096
done
ui_print "Done! Reboot."
UBIN
chmod +x "$PACK/META-INF/com/google/android/update-binary"

(cd "$PACK" && zip -r9 "$ZIP_OUT" . -x "*.DS_Store") &>/dev/null || error "zip failed"

SIGNAPK="$WORK_DIR/bin/signapk.jar"
if [[ -f "$SIGNAPK" ]]; then
  java -jar "$SIGNAPK" "$WORK_DIR/bin/testkey.x509.pem" "$WORK_DIR/bin/testkey.pk8" \
    "$ZIP_OUT" "${ZIP_OUT%.zip}_signed.zip" \
    && mv "${ZIP_OUT%.zip}_signed.zip" "$ZIP_OUT" \
    && log "ZIP подписан" || warn "Подписать не удалось"
fi

log "ZIP готов: $ZIP_OUT ($(du -sh "$ZIP_OUT" | cut -f1))"
