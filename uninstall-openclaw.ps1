<#
.SYNOPSIS
    OpenClaw 卸载脚本 (Windows PowerShell)
.DESCRIPTION
    先停进程 → 移除计划任务 → npm 卸载 → 清理数据
#>

# ---- 编码修复 ----
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $null = & chcp 65001 2>$null
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

function Write-Info  { Write-Host "[INFO]  $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "[WARN]  $args" -ForegroundColor Yellow }
function Write-ErrorMsg { Write-Host "[ERROR] $args" -ForegroundColor Red }
function Write-Step  { Write-Host ""; Write-Host "--- $args ---" -ForegroundColor Cyan }

function Get-InstalledVersion {
    try {
        $o = openclaw --version 2>$null
        if ($o -match '(\d+\.\d+\.\d+)') { return $matches[1] }
        return ""
    } catch { return "" }
}

# ---- 第一步：终止进程 ----
function Stop-AllProcesses {
    Write-Step "停止 OpenClaw 进程"

    # 通过 CLI 停止 gateway（此时命令还在）
    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Write-Info "调用 openclaw gateway stop ..."
        openclaw gateway stop 2>$null
        Start-Sleep -Seconds 1
    }

    # 终止所有相关进程
    $names = @("openclaw", "clawdbot", "moltbot", "node")
    $killed = $false
    foreach ($name in $names) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "openclaw|clawdbot|moltbot" }
        if (-not $procs) {
            # fallback: 按进程名杀死所有同名进程中的可疑项
            $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        }
        foreach ($p in $procs) {
            Write-Info "终止进程: $($p.ProcessName) (PID $($p.Id))"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $killed = $true
        }
    }

    if (-not $killed) { Write-Info "没有运行中的 OpenClaw 进程" }
}

# ---- 第二步：移除计划任务 ----
function Remove-ScheduledTasks {
    Write-Step "移除计划任务"

    $names = @("OpenClawGateway", "OpenClaw", "ClawdbotGateway", "MoltbotGateway")
    $found = $false
    foreach ($n in $names) {
        $task = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
            Write-Info "已移除计划任务: $n"
            $found = $true
        }
    }
    if (-not $found) { Write-Info "没有 openclaw 相关的计划任务" }
}

# ---- 第三步：npm 卸载 ----
function Uninstall-NpmPackage {
    Write-Step "npm 卸载"

    $version = Get-InstalledVersion
    if (-not $version) {
        Write-Info "openclaw 未通过 npm 安装，跳过"
        return
    }

    Write-Info "检测到 openclaw v$version，正在卸载..."
    npm uninstall -g openclaw 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm 卸载返回错误，手动清理..."

        $npmGlobal = npm root -g 2>$null
        if ($npmGlobal) {
            $p = Join-Path $npmGlobal "openclaw"
            if (Test-Path $p) { Remove-Item -Recurse -Force $p; Write-Info "已删除 $p" }
        }
        $npmBin = npm bin -g 2>$null
        if ($npmBin) {
            foreach ($f in @("openclaw", "openclaw.cmd", "clawdbot", "clawdbot.cmd")) {
                $fp = Join-Path $npmBin $f
                Remove-Item -Force $fp -ErrorAction SilentlyContinue
            }
        }
    }

    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Write-Warn "openclaw 命令仍存在: $(Get-Command openclaw | Select-Object -ExpandProperty Source)"
    } else {
        Write-Info "openclaw 已从 npm 全局卸载"
    }
}

# ---- 第四步：清理数据 ----
function Cleanup-Data {
    Write-Step "清理数据"

    Write-Host "以下目录将被删除（如存在）："
    Write-Host "  $env:USERPROFILE\.openclaw\"
    Write-Host "  $env:APPDATA\openclaw\"
    Write-Host "  $env:USERPROFILE\.clawdbot\"
    Write-Host ""

    $confirm = Read-Host "确认删除? [y/N]"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Info "已跳过数据清理"
        return
    }

    $cleaned = $false
    foreach ($d in @(
        (Join-Path $env:USERPROFILE ".openclaw"),
        (Join-Path $env:USERPROFILE ".clawdbot"),
        (Join-Path $env:USERPROFILE ".moltbot")
    )) {
        if (Test-Path $d) { Remove-Item -Recurse -Force $d; Write-Info "已删除 $d"; $cleaned = $true }
    }
    if ($env:APPDATA) {
        $d = Join-Path $env:APPDATA "openclaw"
        if (Test-Path $d) { Remove-Item -Recurse -Force $d; Write-Info "已删除 $d"; $cleaned = $true }
    }

    if (-not $cleaned) { Write-Info "没有需要清理的数据目录" }
}

# ================================================================
function Main {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  OpenClaw 卸载脚本 (Windows)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $v = Get-InstalledVersion
    if ($v) { Write-Host "  已安装版本: v$v" } else { Write-Host "  状态: openclaw 命令未找到（继续清理残留）" }
    Write-Host ""

    Stop-AllProcesses
    Remove-ScheduledTasks
    Uninstall-NpmPackage
    Cleanup-Data

    Write-Host ""
    Write-Info "卸载完成"
    Write-Host ""
}

Main
