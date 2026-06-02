<#
.SYNOPSIS
    OpenClaw 跨平台自动安装/更新脚本 (Windows PowerShell)
.DESCRIPTION
    自动检测 Windows 系统版本，安装 Node.js >= 22，
    配置国内 npm 镜像源，安装/更新 OpenClaw 到最新版本。
    支持 winget / choco / 手动下载三种安装路径。
.NOTES
    推荐右键 -> 以管理员身份运行。
    支持从 CMD 调用: powershell -ExecutionPolicy Bypass -File install-openclaw.ps1
    也可直接运行 install-openclaw.bat（自动下载并执行）
#>

#Requires -Version 5.1

# ---- 编码修复（PowerShell 5.x 控制台不乱码） ----
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $null = & chcp 65001 2>$null
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
}

# ---- 配置 ----
$NPM_MIRROR = "https://registry.npmmirror.com"
$NODE_MIRROR = "https://npmmirror.com/mirrors/node"
$NODE_MIN_MAJOR = 22
$NODE_RECOMMENDED_MAJOR = 24
$Script:NodeInstalledByUs = $false

# ---- 输出函数 ----
function Write-Info  { Write-Host "[INFO]  $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "[WARN]  $args" -ForegroundColor Yellow }
function Write-ErrorMsg { Write-Host "[ERROR] $args" -ForegroundColor Red }
function Write-Step  { Write-Host ""; Write-Host "==> $args" -ForegroundColor Blue }
function Write-Title {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $args" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ---- 系统检测 ----
function Get-OSInfo {
    Write-Step "检测操作系统..."
    $os = Get-CimInstance Win32_OperatingSystem
    $Script:OSCaption = $os.Caption
    $Script:OSVersion = $os.Version
    $Script:OSArch = $os.OSArchitecture

    Write-Host "  操作系统:    $Script:OSCaption"
    Write-Host "  版本号:      $Script:OSVersion"
    Write-Host "  架构:        $Script:OSArch"
    Write-Host ""

    $build = [int]$os.BuildNumber
    if ($build -lt 17763) {
        Write-ErrorMsg "Windows 版本过低（Build $build），需要 Windows 10 1809+ 或 Windows 11"
        Write-ErrorMsg "请升级系统后重试"
        exit 1
    }
}

# ---- 管理员检测 ----
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- 国内网络检测 ----
function Test-CNNetwork {
    try {
        $null = Invoke-WebRequest -Uri "https://registry.npmmirror.com/" -TimeoutSec 3 -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

# ---- Node.js 版本 ----
function Get-NodeMajorVersion {
    try {
        $v = (node -v 2>$null) -replace '^v', ''
        return [int]($v -split '\.')[0]
    } catch {
        return 0
    }
}

function Get-NodeFullVersion {
    try {
        return (node -v 2>$null) -replace '^v', ''
    } catch {
        return "0.0.0"
    }
}

# ---- OpenClaw 版本 ----
function Get-LatestOpenClawVersion {
    param([string]$Registry)
    try {
        $result = npm view openclaw version --registry="$Registry" 2>$null
        return $result.Trim()
    } catch {
        return ""
    }
}

function Get-InstalledOpenClawVersion {
    try {
        $output = openclaw --version 2>$null
        if ($output -match '(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        return ""
    } catch {
        return ""
    }
}

# ---- 安装 Node.js ----
function Install-NodeJS {
    Write-Step "安装 Node.js..."

    $currentMajor = Get-NodeMajorVersion

    if ($currentMajor -ge $NODE_MIN_MAJOR) {
        Write-Info "Node.js $(Get-NodeFullVersion) 已满足最低要求 (>= v$NODE_MIN_MAJOR)"
        return
    }

    if ($currentMajor -gt 0) {
        Write-Warn "当前 Node.js v$currentMajor 不满足要求，将安装 v$NODE_RECOMMENDED_MAJOR LTS..."
    } else {
        Write-Info "Node.js 未安装，将安装 v$NODE_RECOMMENDED_MAJOR LTS..."
    }

    # 方式1: winget（Windows 11 内置 / Windows 10 可安装）
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "使用 winget 安装 Node.js..."
        try {
            winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $currentMajor = Get-NodeMajorVersion
            if ($currentMajor -ge $NODE_MIN_MAJOR) {
                Write-Info "Node.js $(Get-NodeFullVersion) 安装成功（winget）"
                $Script:NodeInstalledByUs = $true
                return
            }
        } catch {
            Write-Warn "winget 安装失败，尝试其他方式..."
        }
    }

    # 方式2: chocolatey
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Info "使用 Chocolatey 安装 Node.js..."
        try {
            choco install nodejs-lts -y 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $currentMajor = Get-NodeMajorVersion
            if ($currentMajor -ge $NODE_MIN_MAJOR) {
                Write-Info "Node.js $(Get-NodeFullVersion) 安装成功（Chocolatey）"
                $Script:NodeInstalledByUs = $true
                return
            }
        } catch {
            Write-Warn "Chocolatey 安装失败，尝试手动下载..."
        }
    }

    # 方式3: 手动下载
    if (Test-CNNetwork) {
        $downloadPage = "https://npmmirror.com/mirrors/node/v${NODE_RECOMMENDED_MAJOR}.x/"
    } else {
        $downloadPage = "https://nodejs.org/dist/v${NODE_RECOMMENDED_MAJOR}.x/"
    }

    Write-Info "请手动下载并安装 Node.js (LTS):"
    Write-Host "  地址: $downloadPage" -ForegroundColor Cyan
    Write-Host ""
    Write-Info "安装完成后重新运行本脚本即可继续"

    $open = Read-Host "是否用浏览器打开下载页面? [Y/n]"
    if ($open -ne "n" -and $open -ne "N") {
        Start-Process $downloadPage
    }
    exit 0
}

# ---- 配置 npm 镜像 ----
function Set-NpmMirror {
    Write-Step "配置 npm 镜像源..."

    if (Test-CNNetwork) {
        Write-Info "配置 npm registry: $NPM_MIRROR"
        npm config set registry "$NPM_MIRROR"
        Write-Info "npm 镜像源已切换至 npmmirror.com"
    } else {
        $currentRegistry = npm config get registry 2>$null
        if ($currentRegistry -match "npmmirror|taobao|mirrors") {
            Write-Warn "当前 npm registry 为国内镜像 ($currentRegistry)"
            Write-Warn "检测到海外网络环境，建议使用官方源"
            $switch = Read-Host "是否切换为官方源? [y/N]"
            if ($switch -eq "y" -or $switch -eq "Y") {
                npm config set registry "https://registry.npmjs.org/"
                Write-Info "已切换为官方 npm 源"
            }
        } else {
            Write-Info "npm registry: $(npm config get registry 2>$null)"
        }
    }
}

# ---- 安装/更新 OpenClaw ----
function Install-OpenClaw {
    Write-Step "安装/更新 OpenClaw..."

    $registry = npm config get registry 2>$null
    if (-not $registry) { $registry = "https://registry.npmjs.org/" }

    Write-Info "正在查询 OpenClaw 最新版本..."
    $latestVersion = Get-LatestOpenClawVersion -Registry $registry

    if (-not $latestVersion) {
        Write-ErrorMsg "无法获取 OpenClaw 最新版本信息，请检查网络连接"
        Write-ErrorMsg "npm registry: $registry"
        exit 1
    }

    Write-Info "OpenClaw 最新版本: v$latestVersion"
    $installedVersion = Get-InstalledOpenClawVersion

    if ($installedVersion) {
        Write-Info "当前已安装版本: v$installedVersion"

        if ($installedVersion -eq $latestVersion) {
            Write-Info "已是最新版本 v$installedVersion，无需更新"
            Show-VersionInfo
            return
        }

        try {
            $iVer = [System.Version]::new($installedVersion)
            $lVer = [System.Version]::new($latestVersion)
            if ($iVer -ge $lVer) {
                Write-Info "当前版本 v$installedVersion 已是最新，无需更新"
                Show-VersionInfo
                return
            }
        } catch { }

        Write-Warn "可更新: v$installedVersion -> v$latestVersion"
        $confirm = Read-Host "是否更新? [Y/n]"
        if ($confirm -eq "n" -or $confirm -eq "N") {
            Write-Info "已跳过更新"
            Show-VersionInfo
            return
        }
    } else {
        Write-Info "OpenClaw 未安装，将安装最新版本 v$latestVersion"
    }

    Write-Info "正在安装 openclaw@$latestVersion..."
    Write-Host ""

    npm install -g "openclaw@$latestVersion"

    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "OpenClaw 安装失败（退出码: $LASTEXITCODE）"
        exit 1
    }

    Write-Host ""

    $newVersion = Get-InstalledOpenClawVersion
    if (-not $newVersion) {
        Write-ErrorMsg "安装后找不到 openclaw 命令，安装可能未成功"
        Write-ErrorMsg "请重新打开终端后再试"
        exit 1
    }

    Write-Info "OpenClaw 安装成功！"

    if ($installedVersion) {
        Write-Info "更新完成: v$installedVersion -> v$newVersion"
    } else {
        Write-Info "安装完成: v$newVersion"
    }

    Write-Host ""
    Show-VersionInfo
}

# ---- 显示版本信息 ----
function Show-VersionInfo {
    Write-Host "--- 环境信息 ---" -ForegroundColor Cyan
    Write-Host "  操作系统:    $Script:OSCaption ($Script:OSVersion)"
    Write-Host "  架构:        $Script:OSArch"
    Write-Host "  Node.js:     $(node -v 2>$null)"
    Write-Host "  npm:         $(npm -v 2>$null)"
    Write-Host "  npm registry: $(npm config get registry 2>$null)"
    Write-Host "  OpenClaw:    $(openclaw --version 2>$null)"
    Write-Host ""
}

# ---- 安装后提示 ----
function Show-PostInstallHelp {
    Write-Title "安装完成！"

    Write-Host "运行以下命令初始化 OpenClaw:"
    Write-Host "  openclaw onboard" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "其他常用命令:"
    Write-Host "  openclaw --version         查看版本"
    Write-Host "  openclaw doctor            检查系统状态"
    Write-Host "  openclaw gateway status    查看网关状态"
    Write-Host ""

    if ($Script:NodeInstalledByUs) {
        Write-Warn "Node.js 刚安装，请重新打开 PowerShell 窗口以使 PATH 生效"
    } else {
        Write-Host "提示: 如找不到 openclaw 命令，请关闭并重新打开终端" -ForegroundColor Cyan
    }
}

# ================================================================
# 主流程
# ================================================================
function Main {
    Write-Title "OpenClaw 跨平台安装脚本 (Windows)"

    if (-not (Test-Admin)) {
        Write-Warn "未以管理员权限运行"
        Write-Warn "安装 Node.js 可能需要管理员权限，如安装失败请右键 -> 以管理员身份运行 PowerShell"
        Write-Host ""
    }

    # 1. 系统检测
    Get-OSInfo

    # 2. 安装 Node.js
    Install-NodeJS

    # 确保 npm 可用
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "npm 不可用，Node.js 安装可能不完整"
        Write-ErrorMsg "请重新打开终端后重试，或手动安装 Node.js: https://nodejs.org/"
        exit 1
    }

    # 3. 配置 npm 镜像
    Set-NpmMirror

    # 4. 安装/更新 OpenClaw
    Install-OpenClaw

    # 5. 完成
    Show-PostInstallHelp
}

Main
