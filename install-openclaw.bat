@echo off
chcp 65001 >nul 2>&1
title OpenClaw Installer

echo ============================================================
echo   OpenClaw Cross-Platform Installer (Windows CMD)
echo ============================================================
echo.

REM Check admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Not running as Administrator.
    echo [WARN] Node.js installation may require admin rights.
    echo [WARN] Right-click this bat file ^> Run as Administrator if install fails.
    echo.
)

REM Download and run the PowerShell script
set "SCRIPT_URL=https://raw.githubusercontent.com/jackorjack/install-openclaw/main/install-openclaw.ps1"
set "LOCAL_PS1=%TEMP%\install-openclaw.ps1"

echo [INFO] Downloading install script...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_PS1%' -UseBasicParsing" 2>&1

if %errorlevel% neq 0 (
    echo [ERROR] Failed to download script from GitHub.
    echo [ERROR] Check network or try manual download:
    echo   %SCRIPT_URL%
    pause
    exit /b 1
)

echo [INFO] Running installer...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_PS1%"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Installation failed. See above for details.
    pause
    exit /b 1
)

echo.
echo [INFO] Done. Run 'openclaw onboard --install-daemon' to initialize.
pause
