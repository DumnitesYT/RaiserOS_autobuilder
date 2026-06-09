#!/usr/bin/env python3
# RaiserOS Telegram Bot
# Все пользователи могут делать до 4 билдов в день
# Владелец (OWNER_ID) без ограничений

import os, sys, logging, requests
from datetime import date
from collections import defaultdict
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

logging.basicConfig(format="%(asctime)s [%(levelname)s] %(message)s", level=logging.INFO)
log = logging.getLogger(__name__)

BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
GH_TOKEN  = os.environ.get("GH_TOKEN", "")
GH_REPO   = os.environ.get("GH_REPO", "")

OWNER_ID   = 6778865145   # без ограничений
DAILY_LIMIT = 4           # для всех остальных

# { user_id: {"date": date, "count": int} }
build_counter = defaultdict(lambda: {"date": None, "count": 0})

HELP = (
    "🔧 *RaiserOS Builder Bot*\n\n"
    "Команды:\n"
    "/build `<URL>` — запустить сборку\n"
    "/status — последние билды\n"
    "/help — справка\n\n"
    "Пример:\n"
    "`/build https://example.com/ColorOS_OTA.zip`\n\n"
    f"_Лимит: {DAILY_LIMIT} билда в день (у владельца без лимита)_"
)

def check_limit(uid: int) -> tuple[bool, int]:
    """Возвращает (можно_билдить, осталось_сегодня)"""
    if uid == OWNER_ID:
        return True, 999
    today = date.today()
    rec = build_counter[uid]
    if rec["date"] != today:
        rec["date"] = today
        rec["count"] = 0
    remaining = DAILY_LIMIT - rec["count"]
    return remaining > 0, remaining

def use_limit(uid: int):
    if uid == OWNER_ID:
        return
    today = date.today()
    rec = build_counter[uid]
    if rec["date"] != today:
        rec["date"] = today
        rec["count"] = 0
    rec["count"] += 1

def trigger_build(rom_url):
    url = f"https://api.github.com/repos/{GH_REPO}/actions/workflows/build.yml/dispatches"
    r = requests.post(url,
        headers={"Authorization": f"Bearer {GH_TOKEN}",
                 "Accept": "application/vnd.github+json"},
        json={"ref": "main", "inputs": {"rom_url": rom_url}},
        timeout=15)
    return r.status_code == 204

def get_runs():
    r = requests.get(
        f"https://api.github.com/repos/{GH_REPO}/actions/runs?per_page=5",
        headers={"Authorization": f"Bearer {GH_TOKEN}",
                 "Accept": "application/vnd.github+json"}, timeout=10)
    return r.json().get("workflow_runs", []) if r.status_code == 200 else []

async def cmd_start(u: Update, _):
    await u.message.reply_text(HELP, parse_mode="Markdown")

async def cmd_help(u: Update, _):
    await u.message.reply_text(HELP, parse_mode="Markdown")

async def cmd_build(u: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid = u.effective_user.id

    # Проверка лимита
    can_build, remaining = check_limit(uid)
    if not can_build:
        await u.message.reply_text(
            f"⛔ Лимит исчерпан!\n"
            f"Ты уже сделал {DAILY_LIMIT} билда сегодня.\n"
            f"Возвращайся завтра 🕛",
            parse_mode="Markdown")
        return

    if not ctx.args:
        await u.message.reply_text(
            "❌ Укажи ссылку:\n`/build https://example.com/OTA.zip`",
            parse_mode="Markdown")
        return

    url = ctx.args[0].strip()
    if not url.startswith("http"):
        await u.message.reply_text("❌ Неверная ссылка. Нужен https://")
        return

    limit_info = "" if uid == OWNER_ID else f"\n_Осталось сегодня: {remaining - 1} из {DAILY_LIMIT}_"
    msg = await u.message.reply_text(
        f"⏳ Запускаю сборку...\n🔗 `{url}`{limit_info}",
        parse_mode="Markdown")

    ok = trigger_build(url)
    if ok:
        use_limit(uid)  # списываем только если успешно
        runs_url = f"https://github.com/{GH_REPO}/actions"
        rem_after = "∞" if uid == OWNER_ID else str(remaining - 1)
        await msg.edit_text(
            f"✅ *Сборка запущена!*\n\n"
            f"🔗 ROM: `{url}`\n"
            f"📊 [Смотреть прогресс]({runs_url})\n"
            f"🔢 Осталось сегодня: {rem_after}\n\n"
            f"_Билд ~30-60 мин. Файл появится в Releases._",
            parse_mode="Markdown")
    else:
        await msg.edit_text(
            "❌ *Ошибка запуска*\n\n"
            "Проверь GH\_TOKEN и что workflow существует в ветке main.",
            parse_mode="Markdown")

async def cmd_status(u: Update, _):
    runs = get_runs()
    if not runs:
        await u.message.reply_text("Нет данных (проверь GH_TOKEN)")
        return
    icons = {"success":"✅","failure":"❌","cancelled":"🚫","in_progress":"⏳","queued":"🕐"}
    lines = ["*Последние билды:*\n"]
    for r in runs[:5]:
        icon = icons.get(r.get("conclusion") or r.get("status",""), "⚠️")
        name = r.get("display_title", r.get("name","Build"))[:40]
        href = r.get("html_url","")
        lines.append(f"{icon} [{name}]({href})")
    await u.message.reply_text("\n".join(lines),
        parse_mode="Markdown", disable_web_page_preview=True)

def main():
    if not BOT_TOKEN: sys.exit("BOT_TOKEN не задан")
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start",  cmd_start))
    app.add_handler(CommandHandler("help",   cmd_help))
    app.add_handler(CommandHandler("build",  cmd_build))
    app.add_handler(CommandHandler("status", cmd_status))
    log.info("RaiserOS bot запущен. Владелец ID: %d", OWNER_ID)
    app.run_polling()

if __name__ == "__main__":
    main()
