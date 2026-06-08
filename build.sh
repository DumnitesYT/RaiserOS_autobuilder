#!/bin/bash

# Цвета для вывода в терминал
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}      RaiserOS Advanced Builder Initializing...   ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. Проверка и получение ссылки
ROM_URL=$1
if [ -z "$ROM_URL" ]; then
    echo -e "${BLUE}[Режим ПК]${NC} Ссылка не передана автоматически."
    echo -n "Введите прямую ссылку на прошивку ColorOS (ZIP): "
    read -r ROM_URL
fi

if [ -z "$ROM_URL" ]; then
    echo -e "${RED}[Ошибка] Ссылка отсутствует! Выход.${NC}"
    exit 1
fi

# Создаем рабочую структуру папок
mkdir -p workspace/input workspace/extracted workspace/output tools

# Установка необходимых линукс-утилит для работы с графикой (если запускается в Ubuntu/GitHub)
if [ -f /etc/debian_version ]; then
    echo -e "${GREEN}[Подготовка]${NC} Установка ImageMagick и зависимостей..."
    sudo apt-get update && sudo apt-get install -y imagemagick default-jr-headless -y
fi

# 2. Скачивание прошивки
echo -e "${GREEN}[1/7]${NC} Скачивание исходного образа прошивки..."
wget -O workspace/input/rom.zip "$ROM_URL"

# 3. Распаковка payload.bin
echo -e "${GREEN}[2/7]${NC} Извлечение разделов из Payload.bin..."
unzip -j workspace/input/rom.zip payload.bin -d workspace/input/
# Используем payload-dumper-go для извлечения нужных разделов
./tools/payload-dumper-go -p system,product,oplus_product,my_manifest -o workspace/extracted/ workspace/input/payload.bin

cd workspace/extracted || exit

# 4. Динамический блюр системных обоев
echo -e "${GREEN}[3/7]${NC} Захват и размытие системных обоев..."
# Ищем системные обои (в ColorOS они могут лежать в разных папках product или system)
SYS_WP=$(find . -type f -name "default_wallpaper.jpg" -o -name "default_wallpaper.png" | head -n 1)

if [ -n "$SYS_WP" ]; then
    echo "Системные обои найдены: $SYS_WP"
    # Блюрим встроенной утилитой convert (из пакета ImageMagick) на 50% и сохраняем временный файл
    convert "$SYS_WP" -blur 0x20 ../../blur_wallpaper.png
    echo "Обои успешно заблюрены и подготовлены."
else
    echo -e "${RED}[Предупреждение]${NC} Дефолтные обои не найдены в образе, используем заглушку."
fi

# 5. Глубокий патч OTA-карточки и текста "Обновление не требуется" -> "RaiserOS 1.0"
echo -e "${GREEN}[4/7]${NC} Декомпиляция OplusOUC.apk (Интерфейс обновлений)..."
# Находим APK системного обновления ColorOS
OTA_APK=$(find . -type f -name "OplusOUC.apk" -o -name "OplusOTA.apk" | head -n 1)

if [ -n "$OTA_APK" ]; then
    echo "Найден APK обновлений: $OTA_APK"
    # Декомпилируем APK через apktool (лежит в папке tools)
    java -jar ../../tools/apktool.jar d "$OTA_APK" -o ota_decompiled -f
    
    echo "Патчинг строковых ресурсов..."
    # Меняем "Обновление не требуется" на "RaiserOS 1.0" во всех файлах локализации strings.xml
    find ota_decompiled/res/ -type f -name "strings.xml" -exec sed -i 's/Обновление не требуется/RaiserOS 1.0/g' {} +
    find ota_decompiled/res/ -type f -name "strings.xml" -exec sed -i 's/Your system is up to date/RaiserOS 1.0/g' {} +

    echo "Интеграция заблюренных обоев в карточку OTA..."
    # Карточка бэкграунда обновлений в OplusOUC обычно называется ota_card_bg, ota_status_bg или аналогично в drawable
    # Ищем все файлы изображений заднего фона в ресурсах приложения и подменяем их нашим блюром
    BG_ASSETS=$(find ota_decompiled/res/ -type f -name "*bg_status*" -o -name "*ota_main_bg*" -o -name "*card_bg*")
    for bg in $BG_ASSETS; do
        cp ../../blur_wallpaper.png "$bg"
        echo "Заменен фон карточки: $bg"
    done

    # Собираем APK обратно
    echo "Рекомпиляция модифицированного APK..."
    java -jar ../../tools/apktool.jar b ota_decompiled -o "$OTA_APK"
    rm -rf ota_decompiled
else
    echo -e "${RED}[Ошибка]${NC} APK обновлений (OplusOUC) не найден!"
fi

# 6. Модификация манифеста (Добавление | RaiserOS к версии прошивки)
echo -e "${GREEN}[5/7]${NC} Модификация системных манифестов и build.prop..."
# Ищем все файлы конфигураций версий
PROP_FILES=$(find . -name "build.prop" -o -name "default.prop")
for prop in $PROP_FILES; do
    # Находим строку отображения версии и добавляем RaiserOS
    sed -i 's/ro.build.display.id=.*/& | RaiserOS/g' "$prop"
    sed -i 's/ro.oplus.display.id=.*/& | RaiserOS/g' "$prop"
done

# 7. Удаление китайского мусора (Debloat)
echo -e "${GREEN}[6/7]${NC} Очистка разделов от bloatware..."
BLOAT_LIST=(
    "product/app/HeyTapAppStation"
    "product/priv-app/HeyTapMarket"
    "product/app/OppoPay"
    "system/system/app/KeenClient"
    "product/app/BreenoSpace"
)
for bloat in "${BLOAT_LIST[@]}"; do
    if [ -d "$bloat" ]; then
        rm -rf "$bloat"
        echo "Удалено мусорное приложение: $bloat"
    fi
done

# 8. Добавление KaorioS Toolbox и Твиков автономности
echo -e "${GREEN}[7/7]${NC} Интеграция KaorioS Toolbox и фиксов автономности..."
# Вшиваем апк как системное приложение
mkdir -p system/system/priv-app/KaorioSToolbox
if [ -f "../../kaorios_toolbox.apk" ]; then
    cp "../../kaorios_toolbox.apk" system/system/priv-app/KaorioSToolbox/KaorioSToolbox.apk
    chmod 644 system/system/priv-app/KaorioSToolbox/KaorioSToolbox.apk
fi

# Добавляем жесткие твики планировщика задач и Doze-режима в build.prop для автономности
cat <<EOT >> system/system/build.prop

# --- RaiserOS Battery Life Battery Fix ---
ro.config.hw_power_saving=true
ro.am.reschedule_service=true
pm.sleep_mode=1
ro.ripple.power.mode=1
wifi.supplicant_scan_interval=240
power_supply.manages.power=1
ro.config.fha_enable=true
ro.sys.fw.bg_apps_limit=32
EOT

# Конец сборки
echo -e "${GREEN}===> Модификация разделов завершена. Упаковка в RaiserOS_Output.zip...${NC}"
# Упаковываем измененные разделы обратно
zip -r ../output/RaiserOS_modified.zip ./*
echo -e "${GREEN}Финал! Все задачи успешно выполнены.${NC}"