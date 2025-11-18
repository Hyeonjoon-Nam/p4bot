@echo off
setlocal

set BASE=C:\p4bot
set LOG=%BASE%\runtime\p4_poller_manual.log

echo [%date% %time%] run_poller >> "%LOG%"

powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%BASE%\p4_poller\p4-poller.ps1" >> "%LOG%" 2>&1
