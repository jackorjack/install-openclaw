<#
.SYNOPSIS
    OpenClaw 卸载脚本 (Windows PowerShell)
.DESCRIPTION
    停止服务、卸载 npm 包、清理残留数据
#>

# ---- 编码修复 ----
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $null = & chcp 65001 2>$null
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# ---- 输出 ----
function Write-Info  { Write-Host "[INFO]  $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "[WARN]  $args" -ForegroundColor Yellow }
function Write-ErrorMsg { Write-Host "[ERROR] $args" -ForegroundColor Red }

# ---- 获取已安装版本 ----
function Get-InstalledVersion {
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

# ---- 停止服务 ----
function Stop-Services {
    Write-Info "正在停止 OpenClaw 服务..."

    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        openclaw gateway stop 2>$null
    }

    # 清理计划任务
    $taskName = "OpenClawGateway"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Info "已移除计划任务: $taskName"
    }

    Write-Info "服务已停止"
}

# ---- npm 卸载 ----
function Uninstall-NpmPackage {
    $version = Get-InstalledVersion

    if (-not $version) {
        Write-Info "未检测到 openclaw（npm 全局），跳过"
        return
    }

    Write-Info "检测到 openclaw v$version，正在卸载..."
    npm uninstall -g openclaw 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm 卸载返回错误码，尝试手动清理..."

        $npmGlobal = npm root -g 2>$null
        if ($npmGlobal) {
            $pkgPath = Join-Path $npmGlobal "openclaw"
            if (Test-Path $pkgPath) {
                Remove-Item -Recurse -Force $pkgPath
                Write-Info "已手动删除: $pkgPath"
            }
        }

        $npmBin = npm bin -g 2>$null
        if ($npmBin) {
            $binPath = Join-Path $npmBin "openclaw"
            $cmdPath = Join-Path $npmBin "openclaw.cmd"
            Remove-Item -Force $binPath -ErrorAction SilentlyContinue
            Remove-Item -Force $cmdPath -ErrorAction SilentlyContinue
        }
    }

    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Write-Warn "卸载后 openclaw 命令仍存在，可能来自其他安装方式"
        Write-Warn "请手动检查: where openclaw"
    } else {
        Write-Info "openclaw 已从 npm 全局卸载"
    }
}

# ---- 清理数据 ----
function Cleanup-Data {
    Write-Host ""
    Write-Warn "是否清理 OpenClaw 数据和配置？"
    Write-Host "这将删除以下目录（如存在）："
    Write-Host "  $env:USERPROFILE\.openclaw\"
    Write-Host "  $env:APPDATA\openclaw\"
    Write-Host ""

    $confirm = Read-Host "确认删除? [y/N]"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Info "已跳过数据清理"
        return
    }

    $cleaned = $false

    $homeDir = Join-Path $env:USERPROFILE ".openclaw"
    if (Test-Path $homeDir) {
        Remove-Item -Recurse -Force $homeDir
        Write-Info "已删除: $homeDir"
        $cleaned = $true
    }

    $appDir = Join-Path $env:APPDATA "openclaw"
    if ($env:APPDATA -and (Test-Path $appDir)) {
        Remove-Item -Recurse -Force $appDir
        Write-Info "已删除: $appDir"
        $cleaned = $true
    }

    if (-not $cleaned) {
        Write-Info "没有需要清理的数据目录"
    }
}

# ================================================================
# 主流程
# ================================================================
function Main {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  OpenClaw 卸载脚本 (Windows)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $version = Get-InstalledVersion
    if ($version) {
        Write-Host "  已安装版本: v$version"
    } else {
        Write-Host "  状态: 未检测到 openclaw"
    }
    Write-Host ""

    Stop-Services
    Uninstall-NpmPackage
    Cleanup-Data

    Write-Host ""
    Write-Info "卸载完成"
    Write-Host ""
}

Main
