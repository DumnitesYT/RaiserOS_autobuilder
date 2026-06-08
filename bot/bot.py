import asyncio
import logging
import os
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
import aiohttp
from aiohttp import web

# ==================== НАСТРОЙКИ КОНФИГУРАЦИИ ====================
TELEGRAM_TOKEN = '8834670603:AAHAkYajK9-k_ddUQOAXqCxu4zdJUPiQko8'
GITHUB_TOKEN = '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'

# ИСПРАВЛЕНО: Убран URL, оставлен чистый путь для API
GITHUB_REPO = 'DumnitesYT/RaiserOS_autobuilder'  
# Убедись, что имя файла совпадает с тем, что лежит в .github/workflows/
WORKFLOW_NAME = 'main.yml'           
# ================================================================

logging.basicConfig(level=logging.INFO)
bot = Bot(token=TELEGRAM_TOKEN)
dp = Dispatcher()

HEADERS = {
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28"
}

# --- КАНАЛ ДЛЯ АВТО-ПИНГА (KEEP ALIVE) ---
# Создаем простой веб-сервер, который требует Render для бесплатных Web Services
async def handle_root(request):
    return web.Response(text="RaiserOS Bot is Alive!")

async def keep_alive_ping():
    """Задача, которая каждые 4 минуты пингует веб-сервер бота, чтобы хостинг не усыплял его"""
    await asyncio.sleep(20)  # Даем время боту запуститься
    
    # Render автоматически выдает URL в переменную окружения, либо используем локальный адрес
    app_url = os.environ.get("RENDER_EXTERNAL_URL", "http://localhost:8080")
    logging.info(f"🚀 Фоновый пинг запущен для адреса: {app_url}")
    
    async with aiohttp.ClientSession() as session:
        while True:
            try:
                async with session.get(app_url) as resp:
                    logging.info(f"💓 Пинг отправлен успешно. Статус: {resp.status}")
            except Exception as e:
                logging.warning(f"🫀 Ошибка авто-пинга (это нормально при локальном старте): {e}")
            
            await asyncio.sleep(240)  # Пауза строго 4 минуты (240 секунд)

# --- ЛОГИКА ТЕЛЕГРАМ БОТА ---
@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    await message.reply(
        "👋 Привет! Я RaiserOS Cloud Bot.\n\n"
        "Я полностью управляю сборкой в облаке GitHub Actions.\n"
        "Чтобы начать сборку модификации, отправь команду:\n"
        "`/build https://ссылка_на_прошивку_coloros.zip`",
        parse_mode="Markdown"
    )

@dp.message(Command("build"))
async def cmd_build(message: types.Message):
    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.reply("❌ Ошибка: Укажи прямую ссылку на zip-архив ColorOS.\nПример: `/build https://site.com/rom.zip`", parse_mode="Markdown")
        return

    rom_url = args[1].strip()
    status_message = await message.reply("⏳ Связываюсь с серверами GitHub для запуска виртуальной машины...")

    url = f"https://api.github.com/repos/{GITHUB_REPO}/actions/workflows/{WORKFLOW_NAME}/dispatches"
    payload = {
        "ref": "main",
        "inputs": {
            "rom_url": rom_url
        }
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(url, json=payload, headers=HEADERS) as response:
            if response.status == 204:
                await status_message.edit_text("🚀 **Облачный компилятор запущен успешно!**\n\nНачался процесс скачивания, блюра обоев и патчинга OTA.\nЯ буду присылать обновления статуса...", parse_mode="Markdown")
                asyncio.create_task(track_github_build(status_message))
            else:
                res_text = await response.text()
                await status_message.edit_text(f"❌ Ошибка запуска на GitHub (Код: {response.status}):\n`{res_text[:200]}`", parse_mode="Markdown")

async def track_github_build(msg: types.Message):
    runs_url = f"https://api.github.com/repos/{GITHUB_REPO}/actions/runs?workflow={WORKFLOW_NAME}&per_page=1"
    await asyncio.sleep(15)
    
    async with aiohttp.ClientSession() as session:
        async with session.get(runs_url, headers=HEADERS) as resp:
            if resp.status != 200:
                await msg.reply("⚠️ Не удалось подключиться к мониторингу, следите за статусом на сайте GitHub.")
                return
            data = await resp.json()
            if not data.get("workflow_runs"):
                await msg.reply("⚠️ Запуск зарегистрирован, но лог выполнения не найден.")
                return
            
            run_id = data["workflow_runs"][0]["id"]
            run_html_url = data["workflow_runs"][0]["html_url"]

        while True:
            await asyncio.sleep(20)
            status_url = f"https://api.github.com/repos/{GITHUB_REPO}/actions/runs/{run_id}"
            
            async with session.get(status_url, headers=HEADERS) as status_resp:
                if status_resp.status != 200:
                    continue
                run_info = await status_resp.json()
                status = run_info.get("status")
                conclusion = run_info.get("conclusion")

                if status == "in_progress":
                    await msg.edit_text(f"⚡ **Статус:** Прошивка модифицируется...\n[Смотреть лог вживую]({run_html_url})", parse_mode="Markdown", disable_web_page_preview=True)
                elif status == "completed":
                    if conclusion == "success":
                        success_text = (
                            "✅ **RaiserOS Успешно Собрана!**\n\n"
                            "• Манифест изменен\n"
                            "• Строка обновления заменена на RaiserOS 1.0\n"
                            "• Системные обои заблюрены и вшиты в OTA-карточку\n"
                            "• Китайский мусор удален\n"
                            "• KaorioS Toolbox интегрирован\n"
                            "• Твики автономности применены\n\n"
                            f"📥 Скачать готовую прошивку:\n[Перейти к файлу в Artifacts]({run_html_url})"
                        )
                        await msg.edit_text(success_text, parse_mode="Markdown")
                    else:
                        await msg.edit_text(f"❌ **Сборка завершилась ошибкой!**\n[Открыть лог ошибки]({run_html_url})", parse_mode="Markdown")
                    break

async def main():
    # Настраиваем веб-сервер параллельно с ботом
    app = web.Application()
    app.router.add_get('/', handle_root)
    runner = web.AppRunner(app)
    await runner.setup()
    # Принимаем входящий порт от хостинга (по умолчанию 8080)
    port = int(os.environ.get("PORT", 8080))
    site = web.TCPSite(runner, '0.0.0.0', port)
    await site.start()
    
    print(f"🤖 Бот запущен! Веб-сервер Keep-Alive слушает порт {port}...")
    
    # Запуск фонового пингалщика
    asyncio.create_task(keep_alive_ping())
    
    # Запуск поллинга Телеграм
    await dp.start_polling(bot)

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Бот остановлен.")
