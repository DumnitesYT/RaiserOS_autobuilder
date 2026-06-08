import os
import subprocess
import logging
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.exceptions import TelegramNetworkError
import asyncio

# Вставьте ваш токен от @BotFather
API_TOKEN = '8834670603:AAHAkYajK9-k_ddUQOAXqCxu4zdJUPiQko8'

# НАСТРОЙКА ПРОКСИ (Если Telegram заблокирован вашим провайдером):
# Если вам нужен прокси для работы бота, раскомментируйте строчку ниже и впишите свой прокси:
# PROXY_URL = "http://username:password@ip:port" 
PROXY_URL = None  # Измените на строку с адресом прокси, если соединение сбрасывается

logging.basicConfig(level=logging.INFO)

# Инициализация сессии с возможностью работы через прокси
session = AiohttpSession(proxy=PROXY_URL) if PROXY_URL else None
bot = Bot(token=API_TOKEN, session=session)
dp = Dispatcher()

@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    start_text = (
        "Привет! Я RaiserOS Builder Bot.\n"
        "Чтобы собрать прошивку, отправь мне команду:\n"
        "/build [прямая_ссылка_на_прошивку]"
    )
    await message.reply(start_text)

@dp.message(Command("build"))
async def cmd_build(message: types.Message):
    args = message.text.split(maxsplit=1)
    
    if len(args) < 2:
        error_msg = "❌ Ошибка: Вы не указали ссылку.\nПример: /build https://domain.com/rom.zip"
        await message.reply(error_msg)
        return

    rom_url = args[1].strip()
    status_msg = f"🚀 Сборка RaiserOS запущена!\n📦 Ссылка: {rom_url}\n\nПроцесс начался на сервере сборщика..."
    await message.reply(status_msg)

    def run_builder(url):
        try:
            # Запуск bash-скрипта сборщика
            # На Windows убедитесь, что Git Bash добавлен в PATH, чтобы команда 'bash' работала
            process = subprocess.Popen(['bash', 'build.sh', url], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = process.communicate()
            return process.returncode, stdout.decode('utf-8', errors='ignore'), stderr.decode('utf-8', errors='ignore')
        except Exception as e:
            return 1, "", str(e)

    # Запуск сборки в отдельном потоке, чтобы не блокировать бота
    loop = asyncio.get_event_loop()
    return_code, out, err = await loop.run_in_executor(None, run_builder, rom_url)

    if return_code == 0:
        await message.reply("✅ Сборка RaiserOS успешно завершена! Модифицированные файлы созданы.")
    else:
        truncated_err = err[:300]
        err_msg = "❌ Ошибка при сборке!\nЛог ошибки:\n" + truncated_err
        await message.reply(err_msg)

async def main():
    print("🤖 Запуск Telegram бота RaiserOS...")
    if PROXY_URL:
        print(f"🌐 Используется прокси-сервер: {PROXY_URL}")
    
    try:
        await dp.start_polling(bot)
    except TelegramNetworkError as net_err:
        print("\n[!] КРИТИЧЕСКАЯ ОШИБКА СЕТИ!")
        print("Бот не может связаться с серверами Telegram (api.telegram.org).")
        print("Возможные решения:")
        print("1. Включите системный VPN на вашем компьютере.")
        print("2. Пропишите рабочий прокси в переменную PROXY_URL в файле bot.py.")
        print("3. Проверьте, не блокирует ли ваш брандмауэр/антивирус интерпретатор Python.")
        print(f"\nДетали ошибки: {net_err}\n")
    except Exception as e:
        print(f"Произошла непредвиденная ошибка: {e}")

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nБот остановлен пользователем.")