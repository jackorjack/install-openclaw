@echo off
chcp 65001 >nul 2>&1
title OpenClaw 安装工具

echo ============================================================
echo   OpenClaw 跨平台安装脚本 (Windows CMD)
echo ============================================================
echo.

REM 检查管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] 未以管理员身份运行
    echo [WARN] 安装 Node.js 可能需要管理员权限
    echo [WARN] 如安装失败，请右键本 bat 文件 -> 以管理员身份运行
    echo.
)

REM 下载并执行 PowerShell 脚本
set "SCRIPT_URL=https://raw.githubusercontent.com/jackorjack/install-openclaw/main/install-openclaw.ps1"
set "LOCAL_PS1=%TEMP%\install-openclaw.ps1"

echo [INFO] 正在下载安装脚本...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_PS1%' -UseBasicParsing" 2>&1

if %errorlevel% neq 0 (
    echo [ERROR] 脚本下载失败，请检查网络连接
    echo [ERROR] 可手动下载: %SCRIPT_URL%
    pause
    exit /b 1
)

echo [INFO] 正在运行安装程序...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_PS1%"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] 安装失败，请查看上方错误信息
    pause
    exit /b 1
)

echo.
echo [INFO] 安装完成。运行 'openclaw onboard --install-daemon' 初始化配置
pause
