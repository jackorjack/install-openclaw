<#
.SYNOPSIS
    OpenClaw cross-platform auto installer/updater (Windows PowerShell)
.DESCRIPTION
    Automatically detects Windows version, installs Node.js >= 22,
    configures npm mirror for China, installs/updates OpenClaw to latest.
.NOTES
    Run as Administrator recommended.
    Also works from CMD: powershell -ExecutionPolicy Bypass -File install-openclaw.ps1
#>

#Requires -Version 5.1

# ---- Config ----
$NPM_MIRROR = "https://registry.npmmirror.com"
$NODE_MIRROR = "https://npmmirror.com/mirrors/node"
$NODE_MIN_MAJOR = 22
$NODE_RECOMMENDED_MAJOR = 24
$Script:NodeInstalledByUs = $false

# ---- Output helpers ----
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

# ---- System detection ----
function Get-OSInfo {
    Write-Step "Detecting OS..."
    $os = Get-CimInstance Win32_OperatingSystem
    $Script:OSCaption = $os.Caption
    $Script:OSVersion = $os.Version
    $Script:OSArch = $os.OSArchitecture

    Write-Host "  OS:          $Script:OSCaption"
    Write-Host "  Version:     $Script:OSVersion"
    Write-Host "  Arch:        $Script:OSArch"
    Write-Host ""

    $build = [int]$os.BuildNumber
    if ($build -lt 17763) {
        Write-ErrorMsg "Windows build $build is too old. Need Windows 10 1809+ or Windows 11."
        exit 1
    }
}

# ---- Admin check ----
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- China network check ----
function Test-CNNetwork {
    try {
        $null = Invoke-WebRequest -Uri "https://registry.npmmirror.com/" -TimeoutSec 3 -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

# ---- Node.js version helpers ----
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

# ---- OpenClaw version helpers ----
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

# ---- Install Node.js ----
function Install-NodeJS {
    Write-Step "Setting up Node.js..."

    $currentMajor = Get-NodeMajorVersion

    if ($currentMajor -ge $NODE_MIN_MAJOR) {
        Write-Info "Node.js $(Get-NodeFullVersion) already meets requirement (>= v$NODE_MIN_MAJOR)"
        return
    }

    if ($currentMajor -gt 0) {
        Write-Warn "Current Node.js v$currentMajor is too old, installing v$NODE_RECOMMENDED_MAJOR LTS..."
    } else {
        Write-Info "Node.js not found, installing v$NODE_RECOMMENDED_MAJOR LTS..."
    }

    # Method 1: winget (built-in on Windows 11 / installable on Windows 10)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Trying winget..."
        try {
            winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $currentMajor = Get-NodeMajorVersion
            if ($currentMajor -ge $NODE_MIN_MAJOR) {
                Write-Info "Node.js $(Get-NodeFullVersion) installed via winget"
                $Script:NodeInstalledByUs = $true
                return
            }
        } catch {
            Write-Warn "winget failed, trying next method..."
        }
    }

    # Method 2: chocolatey
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Info "Trying Chocolatey..."
        try {
            choco install nodejs-lts -y 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $currentMajor = Get-NodeMajorVersion
            if ($currentMajor -ge $NODE_MIN_MAJOR) {
                Write-Info "Node.js $(Get-NodeFullVersion) installed via Chocolatey"
                $Script:NodeInstalledByUs = $true
                return
            }
        } catch {
            Write-Warn "Chocolatey failed, trying manual download..."
        }
    }

    # Method 3: manual download
    if (Test-CNNetwork) {
        $downloadPage = "https://npmmirror.com/mirrors/node/v${NODE_RECOMMENDED_MAJOR}.x/"
    } else {
        $downloadPage = "https://nodejs.org/dist/v${NODE_RECOMMENDED_MAJOR}.x/"
    }

    Write-Info "Please manually download and install Node.js (LTS):"
    Write-Host "  $downloadPage" -ForegroundColor Cyan
    Write-Host ""
    Write-Info "Then re-run this script."

    $open = Read-Host "Open download page in browser? [Y/n]"
    if ($open -ne "n" -and $open -ne "N") {
        Start-Process $downloadPage
    }
    exit 0
}

# ---- Configure npm mirror ----
function Set-NpmMirror {
    Write-Step "Configuring npm registry..."

    if (Test-CNNetwork) {
        Write-Info "Setting npm registry: $NPM_MIRROR"
        npm config set registry "$NPM_MIRROR"
        Write-Info "npm mirror configured (npmmirror.com)"
    } else {
        $currentRegistry = npm config get registry 2>$null
        if ($currentRegistry -match "npmmirror|taobao|mirrors") {
            Write-Warn "Current registry ($currentRegistry) is a China mirror"
            Write-Warn "You appear to be outside China, switching to official registry is recommended"
            $switch = Read-Host "Switch to official registry? [y/N]"
            if ($switch -eq "y" -or $switch -eq "Y") {
                npm config set registry "https://registry.npmjs.org/"
                Write-Info "Switched to official npm registry"
            }
        } else {
            Write-Info "npm registry: $(npm config get registry 2>$null)"
        }
    }
}

# ---- Install/Update OpenClaw ----
function Install-OpenClaw {
    Write-Step "Installing/Updating OpenClaw..."

    $registry = npm config get registry 2>$null
    if (-not $registry) { $registry = "https://registry.npmjs.org/" }

    Write-Info "Querying latest OpenClaw version..."
    $latestVersion = Get-LatestOpenClawVersion -Registry $registry

    if (-not $latestVersion) {
        Write-ErrorMsg "Cannot reach npm registry. Check network."
        Write-ErrorMsg "npm registry: $registry"
        exit 1
    }

    Write-Info "Latest OpenClaw: v$latestVersion"
    $installedVersion = Get-InstalledOpenClawVersion

    if ($installedVersion) {
        Write-Info "Installed version: v$installedVersion"

        if ($installedVersion -eq $latestVersion) {
            Write-Info "Already up-to-date (v$installedVersion). Nothing to do."
            Show-VersionInfo
            return
        }

        try {
            $iVer = [System.Version]::new($installedVersion)
            $lVer = [System.Version]::new($latestVersion)
            if ($iVer -ge $lVer) {
                Write-Info "Current v$installedVersion is up-to-date."
                Show-VersionInfo
                return
            }
        } catch { }

        Write-Warn "Update available: v$installedVersion -> v$latestVersion"
        $confirm = Read-Host "Update now? [Y/n]"
        if ($confirm -eq "n" -or $confirm -eq "N") {
            Write-Info "Skipped update."
            Show-VersionInfo
            return
        }
    } else {
        Write-Info "OpenClaw not installed. Installing v$latestVersion..."
    }

    Write-Info "Running: npm install -g openclaw@$latestVersion"
    Write-Host ""

    npm install -g "openclaw@$latestVersion"

    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Installation failed (exit code: $LASTEXITCODE)"
        exit 1
    }

    Write-Host ""

    $newVersion = Get-InstalledOpenClawVersion
    if (-not $newVersion) {
        Write-ErrorMsg "openclaw command not found after installation."
        Write-ErrorMsg "Please restart your terminal and try again."
        exit 1
    }

    Write-Info "OpenClaw installed successfully!"

    if ($installedVersion) {
        Write-Info "Updated: v$installedVersion -> v$newVersion"
    } else {
        Write-Info "Installed: v$newVersion"
    }

    Write-Host ""
    Show-VersionInfo
}

# ---- Show version info ----
function Show-VersionInfo {
    Write-Host "--- Environment ---" -ForegroundColor Cyan
    Write-Host "  OS:          $Script:OSCaption ($Script:OSVersion)"
    Write-Host "  Arch:        $Script:OSArch"
    Write-Host "  Node.js:     $(node -v 2>$null)"
    Write-Host "  npm:         $(npm -v 2>$null)"
    Write-Host "  npm registry: $(npm config get registry 2>$null)"
    Write-Host "  OpenClaw:    $(openclaw --version 2>$null)"
    Write-Host ""
}

# ---- Post-install help ----
function Show-PostInstallHelp {
    Write-Title "Done!"

    Write-Host "Next steps:"
    Write-Host "  openclaw onboard --install-daemon" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Other commands:"
    Write-Host "  openclaw --version        Show version"
    Write-Host "  openclaw doctor           System health check"
    Write-Host "  openclaw gateway status   Gateway status"
    Write-Host ""

    if ($Script:NodeInstalledByUs) {
        Write-Warn "Node.js was just installed. Restart terminal if PATH isn't updated."
    }
}

# ================================================================
# Main
# ================================================================
function Main {
    Write-Title "OpenClaw Cross-Platform Installer (Windows)"

    if (-not (Test-Admin)) {
        Write-Warn "Not running as Administrator."
        Write-Warn "Node.js installation may require admin rights."
        Write-Warn "If it fails, right-click PowerShell -> Run as Administrator."
        Write-Host ""
    }

    Get-OSInfo
    Install-NodeJS

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "npm is not available. Node.js installation may be incomplete."
        Write-ErrorMsg "Restart terminal and retry, or install Node.js manually: https://nodejs.org/"
        exit 1
    }

    Set-NpmMirror
    Install-OpenClaw
    Show-PostInstallHelp
}

Main
