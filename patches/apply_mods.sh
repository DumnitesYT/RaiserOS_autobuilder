#!/bin/bash
# RaiserOS — применение всех модов

IMAGES="$1"
source "$2"
source "$(dirname "$0")/../functions.sh"

SYS="$IMAGES/system/system"
SYSEXT="$IMAGES/system_ext"
PRODUCT="$IMAGES/product"
VENDOR="$IMAGES/vendor"
P="$(dirname "$0")"

# ══════════════════════════════════════════
# 1. ДЕБLOAT
# ══════════════════════════════════════════
if [[ "$DEBLOAT" == "true" ]]; then
  step "Дебloat: удаляю CN-мусор"
  n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^# || -z "$line" ]] && continue
    t="$IMAGES/$line"
    [[ -e "$t" ]] && rm -rf "$t" && (( n++ )) || true
  done < "$P/debloat.txt"
  log "Удалено: $n элементов"
fi

# ══════════════════════════════════════════
# 2. БРЕНДИНГ
# ══════════════════════════════════════════
step "Брендинг RaiserOS"
for bp in "$SYS/build.prop" "$SYSEXT/build.prop" "$PRODUCT/etc/build.prop" "$VENDOR/build.prop"; do
  [[ -f "$bp" ]] || continue
  # display.id — добавляем | RaiserOS если ещё нет
  if grep -q "ro.build.display.id=" "$bp"; then
    cur=$(grep -m1 "^ro.build.display.id=" "$bp" | cut -d= -f2-)
    if [[ "$cur" != *"$ROM_BRAND"* ]]; then
      python3 -c "
import re, sys
content = open('$bp').read()
content = re.sub(
  r'^ro\.build\.display\.id=(.*)$',
  lambda m: 'ro.build.display.id=' + m.group(1) + ' | $ROM_BRAND',
  content, flags=re.MULTILINE)
open('$bp','w').write(content)
"
    fi
  fi
  # version.ota — добавляем -RaiserOS если ещё нет
  if grep -q "ro.build.version.ota=" "$bp"; then
    cur=$(grep -m1 "^ro.build.version.ota=" "$bp" | cut -d= -f2-)
    if [[ "$cur" != *"$ROM_BRAND"* ]]; then
      python3 -c "
import re
content = open('$bp').read()
content = re.sub(
  r'^ro\.build\.version\.ota=(.*)$',
  lambda m: 'ro.build.version.ota=' + m.group(1) + '-$ROM_BRAND',
  content, flags=re.MULTILINE)
open('$bp','w').write(content)
"
    fi
  fi
  log "Брендинг → $bp"
done

# Кастомные проперти
if [[ -f "$SYS/build.prop" ]] && ! grep -q "ro.raiseros.version" "$SYS/build.prop"; then
  printf "\n# RaiserOS\nro.raiseros.version=%s\nro.raiseros.build.date=%s\n" \
    "$ROM_BRAND_VERSION" "$(date +%Y%m%d)" >> "$SYS/build.prop"
  log "RaiserOS props добавлены"
fi

# ══════════════════════════════════════════
# 3. OTA КАРТОЧКА
# ══════════════════════════════════════════
if [[ "$BRAND_OTA_CARD" == "true" ]]; then
  step "Патчу OTA карточку"
  OTA_APK=""
  for c in \
    "$PRODUCT/priv-app/OplusOTAService/OplusOTAService.apk" \
    "$SYS/priv-app/OPOTAUpdateService/OPOTAUpdateService.apk" \
    "$SYSEXT/priv-app/OplusOTAService/OplusOTAService.apk" \
  ; do [[ -f "$c" ]] && OTA_APK="$c" && break; done
  [[ -z "$OTA_APK" ]] && \
    OTA_APK=$(find "$IMAGES" -path "*/priv-app/*OTA*.apk" 2>/dev/null | head -1)

  if [[ -n "$OTA_APK" ]] && command -v apktool &>/dev/null; then
    D="/tmp/ota_d"; rm -rf "$D"
    apktool d -f -o "$D" "$OTA_APK" &>/dev/null && {
      find "$D/res" -name "strings.xml" | while read -r sx; do
        python3 -c "
import re
txt = open('$sx').read()
for old in ['Обновление не требуется','Нет доступных обновлений',
            'Нет обновлений','Уже последняя версия',
            'No update available','System is up to date',
            'Already the latest version','Your system is up to date']:
    txt = txt.replace('>'+old+'<', '>$ROM_BRAND $ROM_BRAND_VERSION<')
open('$sx','w').write(txt)
"
      done
      apktool b "$D" -o "${OTA_APK%.apk}_new.apk" &>/dev/null \
        && mv "${OTA_APK%.apk}_new.apk" "$OTA_APK" \
        && log "OTA строки заменены ✓" || warn "apktool recompile не удался"
      rm -rf "$D"
    } || warn "apktool decode не удался"
  else
    [[ -z "$OTA_APK" ]] && warn "OTA APK не найден" || warn "apktool не установлен"
  fi

  BG="$P/wallpaper/ota_bg.jpg"
  if [[ -f "$BG" ]]; then
    for res_dir in \
      "$PRODUCT/app/OplusOTAUI/res/drawable" \
      "$PRODUCT/app/OplusOTAUI/res/drawable-xxhdpi-v4" \
      "$SYS/app/OPOTAUpdateService/res/drawable" \
    ; do
      [[ -d "$res_dir" ]] || continue
      for name in ota_check_bg.png ota_bg.png no_update_bg.png ic_update_bg.png; do
        [[ -f "$res_dir/$name" ]] && cp "$BG" "$res_dir/$name" && log "Обои → $res_dir/$name"
      done
    done
  else
    warn "Обои не найдены: patches/wallpaper/ota_bg.jpg"
  fi
fi

# ══════════════════════════════════════════
# 4. ОТКЛЮЧАЕМ OTA UPDATER
# ══════════════════════════════════════════
if [[ "$DISABLE_OTA" == "true" ]]; then
  step "Отключаю OTA updater"
  for d in \
    "$SYS/app/OPOTAUpdateService" \
    "$SYS/priv-app/OPOTAUpdateService" \
    "$SYSEXT/priv-app/OplusOTAService" \
    "$PRODUCT/priv-app/OplusOTAService" \
  ; do [[ -d "$d" ]] && rm -rf "$d" && log "Удалён: $(basename $d)"; done
  perm="$SYS/etc/permissions/android.software.update_packages_on_user.xml"
  [[ -f "$perm" ]] && rm -f "$perm" && log "OTA permissions удалены"
fi

# ══════════════════════════════════════════
# 5. ФИКС БАТАРЕИ
# ══════════════════════════════════════════
if [[ "$FIX_BATTERY" == "true" ]]; then
  step "Фикс батареи"
  for bp in "$SYS/build.prop" "$VENDOR/build.prop" "$VENDOR/default.prop"; do
    [[ -f "$bp" ]] || continue
    sed -i 's/^ro\.vendor\.qti\.config\.disable_app_standby=.*/ro.vendor.qti.config.disable_app_standby=1/' "$bp" || true
    sed -i 's/^ro\.config\.low_ram=.*/ro.config.low_ram=false/' "$bp" || true
    grep -v "^persist\.sys\.oplus\.powersave" "$bp" > /tmp/bp_tmp && mv /tmp/bp_tmp "$bp" || true
    log "Battery props → $bp"
  done
  bp="$SYS/build.prop"
  if [[ -f "$bp" ]] && ! grep -q "ro.raiseros.battery_fix" "$bp"; then
    printf "\n# RaiserOS battery fix\nro.raiseros.battery_fix=1\nro.config.low_ram=false\npersist.sys.fflag.override.settings_dynamic_system=false\npm.dexopt.bg-dexopt=speed\n" >> "$bp"
    log "Battery fix props добавлены"
  fi
fi

# ══════════════════════════════════════════
# 6. ФИКС GOOGLE PLAY
# ══════════════════════════════════════════
if [[ "$FIX_GOOGLE_PLAY" == "true" ]]; then
  step "Фикс Google Play Integrity"
  bp="$SYS/build.prop"
  if [[ -f "$bp" ]]; then
    grep -q "ro.product.first_api_level" "$bp" || echo "ro.product.first_api_level=31" >> "$bp"
    fp_file="$P/cts_fingerprint.txt"
    if [[ -f "$fp_file" ]]; then
      fp=$(grep -v '^#' "$fp_file" | grep -v '^$' | head -1 | tr -d '[:space:]')
      [[ -n "$fp" ]] && {
        sed -i "s|^ro\.build\.fingerprint=.*|ro.build.fingerprint=$fp|" "$bp"
        sed -i "s|^ro\.bootimage\.build\.fingerprint=.*|ro.bootimage.build.fingerprint=$fp|" "$bp"
        log "CTS fingerprint применён"
      }
    fi
  fi
fi

# ══════════════════════════════════════════
# 7. KAORI TOOLBOX
# ══════════════════════════════════════════
if [[ "$INSTALL_KAORI_TOOLBOX" == "true" ]]; then
  step "Устанавливаю KaoriOS Toolbox"
  APK="$WORK_DIR/patches/kaori_toolbox.apk"
  if [[ -f "$APK" ]]; then
    DEST="$PRODUCT/app/KaoriosToolbox"
    mkdir -p "$DEST"
    cp "$APK" "$DEST/KaoriosToolbox.apk"
    log "KaoriOS Toolbox → $DEST ✓"
  else
    warn "kaori_toolbox.apk не найден → patches/kaori_toolbox.apk"
  fi
fi

# ══════════════════════════════════════════
# 8. HOSTS
# ══════════════════════════════════════════
if [[ "$ADD_HOSTS_BLOCKER" == "true" ]]; then
  [[ -f "$P/hosts" && -f "$SYS/etc/hosts" ]] && {
    cat "$P/hosts" >> "$SYS/etc/hosts"
    log "Hosts инжектирован"
  } || warn "patches/hosts не найден"
fi

log "Все моды применены ✓"
