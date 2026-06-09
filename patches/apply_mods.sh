#!/bin/bash
# RaiserOS — применение всех модов
# Вызывается из build.sh: apply_mods.sh <IMAGES_DIR> <CONFIG>

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
# 2. БРЕНДИНГ build.prop + манифест
# ══════════════════════════════════════════
step "Брендинг RaiserOS"
for bp in "$SYS/build.prop" "$SYSEXT/build.prop" "$PRODUCT/etc/build.prop" "$VENDOR/build.prop"; do
  [[ -f "$bp" ]] || continue
  sed -i "s|^\(ro\.build\.display\.id=\)\(.*\)|\1\2 | ${ROM_BRAND}|" "$bp"
  sed -i "s|^\(ro\.build\.version\.ota=\)\(.*\)|\1\2-${ROM_BRAND}|"  "$bp"
  log "Брендинг → $bp"
done
bp="$SYS/build.prop"
if [[ -f "$bp" ]] && ! grep -q "ro.raiseros.version" "$bp"; then
  printf "\n# RaiserOS\nro.raiseros.version=%s\nro.raiseros.build.date=%s\n" \
    "$ROM_BRAND_VERSION" "$(date +%Y%m%d)" >> "$bp"
fi

# ══════════════════════════════════════════
# 3. OTA КАРТОЧКА
# Строка "Обновление не требуется" живёт в
# com.oplus.ota APK → res/values*/strings.xml
# APK: product/priv-app/OplusOTAService/
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
    log "OTA APK: $OTA_APK"
    D="/tmp/ota_d"; rm -rf "$D"
    apktool d -f -o "$D" "$OTA_APK" &>/dev/null && {
      find "$D/res" -name "strings.xml" | while read -r sx; do
        sed -i \
          -e "s|>Обновление не требуется<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          -e "s|>Нет доступных обновлений<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          -e "s|>Нет обновлений<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          -e "s|>Уже последняя версия<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          -e "s|>No update available<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          -e "s|>System is up to date<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          -e "s|>Already the latest version<|>${ROM_BRAND} ${ROM_BRAND_VERSION}<|g" \
          "$sx"
      done
      apktool b "$D" -o "${OTA_APK%.apk}_new.apk" &>/dev/null \
        && mv "${OTA_APK%.apk}_new.apk" "$OTA_APK" \
        && log "OTA строки заменены ✓" || warn "apktool recompile не удался"
      rm -rf "$D"
    } || warn "apktool decode не удался"
  else
    [[ -z "$OTA_APK" ]] && warn "OTA APK не найден" || warn "apktool не установлен"
  fi

  # Инжектируем заблюренные обои в drawable OTA-приложения
  BG="$P/wallpaper/ota_bg.jpg"
  if [[ -f "$BG" ]]; then
    for res_dir in \
      "$PRODUCT/app/OplusOTAUI/res/drawable" \
      "$PRODUCT/app/OplusOTAUI/res/drawable-xxhdpi-v4" \
      "$SYS/app/OPOTAUpdateService/res/drawable" \
    ; do
      [[ -d "$res_dir" ]] || continue
      for name in ota_check_bg.png ota_bg.png no_update_bg.png ic_update_bg.png; do
        [[ -f "$res_dir/$name" ]] && cp "$BG" "$res_dir/$name" \
          && log "Обои → $res_dir/$name"
      done
    done
  else
    warn "Обои не найдены: patches/wallpaper/ota_bg.jpg"
    warn "  → Положи заблюренную картинку туда чтобы включить"
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
    sed -i 's|^ro\.vendor\.qti\.config\.disable_app_standby=.*|ro.vendor.qti.config.disable_app_standby=1|' "$bp"
    sed -i 's|^ro\.config\.low_ram=.*|ro.config.low_ram=false|' "$bp"
    sed -i '/^persist\.sys\.oplus\.powersave/d' "$bp"
    log "Battery props → $bp"
  done
  bp="$SYS/build.prop"
  if [[ -f "$bp" ]] && ! grep -q "ro.raiseros.battery_fix" "$bp"; then
    printf "\n# RaiserOS battery fix\nro.raiseros.battery_fix=1\nro.config.low_ram=false\npersist.sys.fflag.override.settings_dynamic_system=false\npm.dexopt.bg-dexopt=speed\n" >> "$bp"
    log "Battery fix props добавлены"
  fi
fi

# ══════════════════════════════════════════
# 6. ФИКС GOOGLE PLAY / CTS
# ══════════════════════════════════════════
if [[ "$FIX_GOOGLE_PLAY" == "true" ]]; then
  step "Фикс Google Play Integrity"
  bp="$SYS/build.prop"
  if [[ -f "$bp" ]]; then
    grep -q "ro.product.first_api_level" "$bp" || echo "ro.product.first_api_level=31" >> "$bp"
    fp_file="$P/cts_fingerprint.txt"
    if [[ -f "$fp_file" ]]; then
      fp=$(grep -v '^#' "$fp_file" | head -1 | tr -d '[:space:]')
      [[ -n "$fp" ]] && {
        sed -i "s|^ro\.build\.fingerprint=.*|ro.build.fingerprint=$fp|" "$bp"
        sed -i "s|^ro\.bootimage\.build\.fingerprint=.*|ro.bootimage.build.fingerprint=$fp|" "$bp"
        log "CTS fingerprint применён"
      }
    else
      warn "cts_fingerprint.txt не найден — пропуск"
    fi
  fi
fi

# ══════════════════════════════════════════
# 7. KAORI TOOLBOX
# ══════════════════════════════════════════
if [[ "$INSTALL_KAORI_TOOLBOX" == "true" ]]; then
  step "Устанавливаю KaoriOS Toolbox"
  tz="$WORK_DIR/patches/kaori_toolbox.zip"
  if [[ -f "$tz" ]]; then
    T="/tmp/kaori_tb"; rm -rf "$T"; mkdir "$T"
    unzip -q "$tz" -d "$T"
    [[ -d "$T/system"  ]] && cp -rf "$T/system/."  "$SYS/"     && log "Toolbox → system"
    [[ -d "$T/product" ]] && cp -rf "$T/product/." "$PRODUCT/" && log "Toolbox → product"
    [[ -d "$T/vendor"  ]] && cp -rf "$T/vendor/."  "$VENDOR/"  && log "Toolbox → vendor"
    rm -rf "$T"
    log "KaoriOS Toolbox установлен ✓"
  else
    warn "kaori_toolbox.zip не найден → положи в patches/kaori_toolbox.zip"
  fi
fi

# ══════════════════════════════════════════
# 8. HOSTS (опционально)
# ══════════════════════════════════════════
if [[ "$ADD_HOSTS_BLOCKER" == "true" ]]; then
  [[ -f "$P/hosts" && -f "$SYS/etc/hosts" ]] && {
    cat "$P/hosts" >> "$SYS/etc/hosts"
    log "Hosts инжектирован"
  } || warn "patches/hosts не найден"
fi

log "Все моды применены ✓"
