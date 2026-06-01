# OpenClaw 跨平台一键安装脚本

自动检测操作系统，安装 Node.js LTS，配置国内镜像加速，安装/更新 OpenClaw 到最新版本。

## 一键安装

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/jackorjack/install-openclaw/main/install-openclaw.sh | bash
```

### Windows（PowerShell 管理员模式）

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; iwr -useb https://raw.githubusercontent.com/jackorjack/install-openclaw/main/install-openclaw.ps1 | iex
```

> 如遇权限问题，右键 PowerShell → 以管理员身份运行。

---

## 脚本做了什么

| 步骤 | macOS | Linux | Windows |
|------|-------|-------|---------|
| 检测系统 | 版本、架构、包管理器 | 发行版、包管理器 | 版本、架构 |
| 安装 Node.js | 先装 Homebrew（USTC 源）→ `brew install node` | nvm → NodeSource apt/rpm → pacman | winget → Chocolatey → 手动下载页 |
| npm 镜像 | 国内自动切 `npmmirror.com` | 同左 | 同左 |
| OpenClaw | `npm install -g openclaw@latest` | 同左 | 同左 |
| 版本判断 | 已最新跳过 / 可更新提示 / 未安装直接装 | 同左 | 同左 |

**国内网络环境下所有下载自动走国内镜像：**

| 组件 | 海外 | 国内镜像 |
|------|------|---------|
| npm registry | `registry.npmjs.org` | `registry.npmmirror.com` |
| Node.js 二进制 | `nodejs.org` | `npmmirror.com/mirrors/node` |
| Homebrew (macOS) | 官方源 | USTC mirrors |
| nvm 安装脚本 | GitHub raw | Gitee mirrors |

---

## 手动下载运行

如果不方便直接 pipe，可以先下载再运行：

```bash
# macOS / Linux
curl -O https://raw.githubusercontent.com/jackorjack/install-openclaw/main/install-openclaw.sh
bash install-openclaw.sh
```

```powershell
# Windows PowerShell
iwr -useb https://raw.githubusercontent.com/jackorjack/install-openclaw/main/install-openclaw.ps1 -OutFile install-openclaw.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install-openclaw.ps1
```

---

## 运行效果示例

```
============================================================
  OpenClaw 跨平台安装脚本
============================================================

==> 检测操作系统...
  操作系统:    macOS
  版本:        15.4
  包管理器:    brew

==> 安装 Node.js (macOS)...
[INFO]  Node.js v22.19.0 已满足最低要求 (≥ v22)

==> 配置 npm 镜像源...
[INFO]  配置 npm registry: https://registry.npmmirror.com

==> 安装/更新 OpenClaw...
[INFO]  正在查询 OpenClaw 最新版本...
[INFO]  OpenClaw 最新版本: v2026.5.28
[INFO]  当前已安装版本: v2026.5.22
[WARN]  可更新: v2026.5.22 → v2026.5.28
是否更新? [Y/n]

[INFO]  ✓ OpenClaw 安装成功！
[INFO]  更新完成: v2026.5.22 → v2026.5.28

--- 环境信息 ---
  操作系统:    macOS 15.4
  Node.js:     v22.19.0
  npm:         10.9.3
  npm registry: https://registry.npmmirror.com
  OpenClaw:    2026.5.28
```

---

## 安装后

```bash
# 首次初始化（配置模型和通道，安装后台守护进程）
openclaw onboard --install-daemon

# 查看版本
openclaw --version

# 健康检查
openclaw doctor

# 查看网关状态
openclaw gateway status
```

---

## 系统要求

| 项目 | 最低要求 |
|------|---------|
| macOS | 12+ (Monterey) |
| Linux | Ubuntu 22.04+ / Debian 12+ / CentOS 8+ / Fedora 38+ / Arch |
| Windows | 10 1809+ 或 11 |
| Node.js | ≥ v22（脚本自动安装，推荐 v24 LTS） |
| 内存 | ≥ 2GB |
| 磁盘 | ≥ 5GB 可用空间 |

---

## 常见问题

### 国内下载慢或失败？
脚本默认检测网络环境，国内自动切换 `npmmirror.com` 镜像。如仍有问题，可能是 curl/wget 首次下载 GitHub raw 较慢，手动下载脚本后运行即可。

### macOS 提示「无法验证开发者」？
```bash
sudo spctl --master-disable  # 临时允许非 App Store 应用
# 或右键脚本文件 → 打开 → 仍要打开
```

### Linux 非 root 用户无法 sudo？
脚本优先通过 nvm 安装 Node.js（用户目录，无需 sudo）。仅在 nvm 不可用时才回退到系统包管理器。

### Windows 脚本执行被阻止？
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
此命令仅对当前 PowerShell 窗口生效，不影响系统安全策略。

### 安装后找不到 openclaw 命令？
关闭并重新打开终端，使 PATH 环境变量生效。
