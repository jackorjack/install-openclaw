@echo off
chcp 65001 >nul 2>&1
title OpenClaw 卸载工具

echo ============================================================
echo   OpenClaw 卸载脚本 (Windows CMD)
echo ============================================================
echo.

REM 下载并执行 PowerShell 卸载脚本
set "SCRIPT_URL=https://raw.githubusercontent.com/jackorjack/install-openclaw/main/uninstall-openclaw.ps1"
set "LOCAL_PS1=%TEMP%\uninstall-openclaw.ps1"

echo [INFO] 正在下载卸载脚本...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_PS1%' -UseBasicParsing" 2>&1

if %errorlevel% neq 0 (
    echo [ERROR] 脚本下载失败，请检查网络连接
    pause
    exit /b 1
)

echo [INFO] 正在执行卸载...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_PS1%"

echo [INFO] 卸载完成
pause
