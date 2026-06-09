# Как залить RaiserOS Builder на GitHub

## Шаг 1 — Создай репозиторий

1. Зайди на github.com → кнопка "+" → New repository
2. Название: `raiseros-builder`
3. Visibility: **Private**
4. Галочку "Add README" — НЕ ставь
5. Create repository

---

## Шаг 2 — Создай токен (PAT)

1. GitHub → Settings (аватар) → Developer settings
2. Personal access tokens → Tokens (classic)
3. Generate new token (classic)
4. Галочки: ✅ `repo` + ✅ `workflow`
5. Скопируй токен — он показывается ОДИН РАЗ
   Выглядит так: `ghp_xxxxxxxxxxxxxxxxxxxx`

---

## Шаг 3 — Залей файлы

Открой терминал в папке raiseros-builder:

```bash
git init
git add .
git commit -m "Initial RaiserOS builder"
git remote add origin https://github.com/ТВОЙник/raiseros-builder.git
git push -u origin main
```

При запросе пароля — вставь токен из Шага 2.

---

## Шаг 4 — Добавь секрет GH_TOKEN

1. Открой репо → Settings → Secrets and variables → Actions
2. New repository secret:
   - Name: `GH_TOKEN`
   - Value: токен из Шага 2
3. Add secret

---

## Шаг 5 — Запусти билд

1. Репо → вкладка Actions
2. Слева: "Build RaiserOS" → Run workflow
3. Вставь ссылку на ColorOS OTA .zip
4. Run workflow

Билд займёт 30-60 минут.
Готовый ZIP появится в Actions → артефакты → и в Releases.

---

## Шаг 6 — Настрой Telegram бота (опционально)

### Создай бота:
1. Напиши @BotFather → /newbot
2. Получишь токен: `123456789:AAxxxxx`

### Узнай свой Telegram ID:
Напиши @userinfobot — ответит числом.

### Запусти:
```bash
cd bot
pip install -r requirements.txt
cp .env.example .env
# Заполни .env своими данными
nano .env
python3 bot.py
```

### Команды бота:
```
/build https://example.com/ColorOS_OTA.zip
/status
/help
```

---

## Что нужно добавить вручную

| Файл | Откуда взять |
|------|-------------|
| `bin/fspatch.py` | NothingsVN/oplus-toolbuild → bin/ |
| `bin/contextpatch.py` | то же репо |
| `bin/ext4_extract.py` | то же репо |
| `patches/wallpaper/ota_bg.jpg` | Своя заблюренная картинка |
| `patches/kaori_toolbox.zip` | Скачай KaoriOS Toolbox |
| `patches/cts_fingerprint.txt` | Вставь fingerprint устройства |

После добавления файлов:
```bash
git add .
git commit -m "Add patches and bin scripts"
git push
```
