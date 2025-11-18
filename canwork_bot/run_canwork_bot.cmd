@echo off
setlocal

set BASE=C:\p4bot

cd /d %BASE%

"C:\Users\h\AppData\Local\Programs\Python\Python312\python.exe" ^
  "%BASE%\canwork_bot\p4_canwork_bot.py" >> "%BASE%\runtime\canwork_bot.log" 2>&1
