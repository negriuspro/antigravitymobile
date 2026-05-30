@echo off
title ANTIGRAVITY HUB

set BASE_DIR=%~dp0

cd /d "%BASE_DIR%hub"

echo ====================================
echo   STARTING ANTIGRAVITY HUB
echo ====================================

start "HUB" cmd /k "python main.py"

timeout /t 3 >nul

for /f "tokens=2 delims=:" %%f in ('ipconfig ^| findstr /C:"IPv4"') do (
    set IP=%%f
    goto done
)

:done
set IP=%IP: =%

echo.
echo HUB LAN:
echo http://%IP%:8080
echo http://%IP%:8080/docs
echo ====================================

start http://localhost:8080/docs

pause