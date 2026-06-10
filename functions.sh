#!/bin/bash
# RaiserOS — общие утилиты

RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'; NC='\033[0m'
log()   { echo -e "[${GRN}INFO${NC}]  $*"; }
warn()  { echo -e "[${YEL}WARN${NC}]  $*"; }
error() { echo -e "[${RED}ERR ${NC}]  $*"; exit 1; }
step()  { echo -e "\n[${GRN}=====${NC}] $*"; }

check() {
  local miss=()
  for t in "$@"; do command -v "$t" &>/dev/null || miss+=("$t"); done
  [[ ${#miss[@]} -gt 0 ]] && error "Не найдены: ${miss[*]}. Запусти setup.sh"
  log "Все зависимости OK"
}

download_rom() {
  local url="$1" dest="$2"
  log "Скачиваю: $url"
  aria2c -x16 -s16 -k1M --continue=true --console-log-level=warn \
    -o "$(basename "$dest")" -d "$(dirname "$dest")" "$url" \
    || error "Ошибка загрузки"
}

detect_fs() {
  local img="$1"
  file "$img" 2>/dev/null | grep -qi erofs && echo "EROFS" && return
  local magic; magic=$(xxd -l4 -p "$img" 2>/dev/null)
  [[ "$magic" == *"e2e1"* || "$magic" == *"e0f5"* ]] && echo "EROFS" || echo "EXT"
}

extract_partition() {
  local img="$1" out="$2"
  local name; name=$(basename "${img%.img}")
  local dest="$out/$name"
  mkdir -p "$dest" "$out/config"
  local fs; fs=$(detect_fs "$img")
  echo "$fs" > "$out/config/${name}_fstype"
  log "Извлекаю [$name] [$fs]..."
  case "$fs" in
    EXT)
      debugfs -R "rdump / $dest" "$img" &>/dev/null \
        || error "EXT extract $name"
      ;;
    EROFS)
      "$WORK_DIR/bin/Linux/x86_64/extract.erofs" -i "$img" -o "$dest" &>/dev/null \
        || error "EROFS extract $name"
      ;;
  esac
}

repack_partition() {
  local name="$1" images="$2"
  local src="$images/$name"
  local out="$images/${name}.img"
  local cfg="$images/config"
  [[ -d "$src" ]] || { warn "Нет папки $name — пропуск"; return; }

  python3 "$WORK_DIR/bin/fspatch.py"      "$src" "$cfg/${name}_fs_config"     &>/dev/null
  python3 "$WORK_DIR/bin/contextpatch.py" "$src" "$cfg/${name}_file_contexts" &>/dev/null

  local raw; raw=$(du -sb "$src" | awk '{print $1}')
  local pad=134217728
  case "$name" in
    system|system_ext|vendor) pad=154217728 ;;
    product) pad=204217728 ;;
  esac
  local size=$(( raw + pad ))

  local fs="${REPACK_TYPE:-auto}"
  [[ "$fs" == "auto" ]] && fs=$(cat "$cfg/${name}_fstype" 2>/dev/null || echo EXT)

  echo -ne "[REPACK] [$name] [$fs]... "
  case "$fs" in
    EXT)
      make_ext4fs -J -T "$(date +%s)" \
        -S "$cfg/${name}_file_contexts" \
        -l "$size" -C "$cfg/${name}_fs_config" \
        -L "$name" -a "$name" \
        "$out" "$src" &>/dev/null || error "EXT repack $name"
      ;;
    EROFS)
      mkfs.erofs --quiet -zlz4hc,"${COMPRESS_LEVEL:-9}" \
        --mount-point="$name" \
        --fs-config-file="$cfg/${name}_fs_config" \
        --file-contexts="$cfg/${name}_file_contexts" \
        "$out" "$src" &>/dev/null || error "EROFS repack $name"
      ;;
  esac
  echo "OK"
}

remove_fsv() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  find "$d" \\( -name "*.fsv_meta" -o -name "*.avbpubkey" \\) -delete 2>/dev/null || true
}

fetch_rom_info() {
  local sysdir="$1"
  local prop=""
  for candidate in \
    "$sysdir/system/build.prop" \
    "$sysdir/build.prop" \
    "$sysdir/system/system/build.prop" \
  ; do
    [[ -f "$candidate" ]] && prop="$candidate" && break
  done
  if [[ -z "$prop" ]]; then
    prop=$(find "$sysdir" -maxdepth 4 -name "build.prop" 2>/dev/null | head -1)
  fi
  if [[ -z "$prop" ]]; then
    warn "build.prop не найден — продолжаю с дефолтами"
    ROM_DEVICE="unknown"; ROM_VERSION="unknown"; ROM_BUILD_DATE="$(date +%Y%m%d)"
    return
  fi
  log "build.prop: $prop"
  ROM_DEVICE=$(grep -m1 "ro.product.device=" "$prop" | cut -d= -f2)
  [[ -z "$ROM_DEVICE" ]] && ROM_DEVICE=$(grep -m1 "ro.product.system.device=" "$prop" | cut -d= -f2)
  ROM_VERSION=$(grep -m1 "ro.build.version.ota=" "$prop" | cut -d= -f2)
  [[ -z "$ROM_VERSION" ]] && ROM_VERSION=$(grep -m1 "ro.build.display.id=" "$prop" | cut -d= -f2)
  [[ -z "$ROM_VERSION" ]] && ROM_VERSION=$(grep -m1 "ro.build.id=" "$prop" | cut -d= -f2)
  local utc; utc=$(grep -m1 "ro.build.date.utc=" "$prop" | cut -d= -f2)
  if [[ -n "$utc" ]]; then
    ROM_BUILD_DATE=$(date -d "@$utc" +%Y%m%d 2>/dev/null || date +%Y%m%d)
  else
    ROM_BUILD_DATE="$(date +%Y%m%d)"
  fi
  log "Device: ${ROM_DEVICE:-?}  Ver: ${ROM_VERSION:-?}  Date: ${ROM_BUILD_DATE:-?}"
}
