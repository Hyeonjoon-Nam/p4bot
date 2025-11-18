@echo off
setlocal

set BASE=C:\p4bot
set LOG=%BASE%\runtime\opened_watcher_manual.log

echo [%date% %time%] run_opened_watcher >> "%LOG%"

powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%BASE%\opened_watcher\opened_watcher_min.ps1" ^
  -DepotPath "//your_depot/..." >> "%LOG%" 2>&1
