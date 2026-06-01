#!/usr/bin/env bash
# ============================================================
# OpenClaw 跨平台卸载脚本
# 支持: macOS / Linux / Windows (WSL/Git Bash)
# ============================================================

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() { command -v "$1" &>/dev/null; }

# -----------------------------------------------------------
# 获取已安装版本
# -----------------------------------------------------------
get_installed_version() {
    if command_exists openclaw; then
        openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        echo ""
    fi
}

# 获取 npm 全局安装路径
get_npm_global_path() {
    npm root -g 2>/dev/null || echo ""
}

# -----------------------------------------------------------
# 停止服务
# -----------------------------------------------------------
stop_services() {
    log_info "正在停止 OpenClaw 相关服务..."

    # 停止 gateway 守护进程
    if command_exists openclaw; then
        openclaw gateway stop 2>/dev/null || true
    fi

    # 清理可能的 launchd/systemd 服务
    if [ -f "$HOME/Library/LaunchAgents/com.openclaw.gateway.plist" ]; then
        launchctl unload "$HOME/Library/LaunchAgents/com.openclaw.gateway.plist" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/com.openclaw.gateway.plist"
        log_info "已移除 macOS LaunchAgent"
    fi

    if [ -f "$HOME/.config/systemd/user/openclaw-gateway.service" ]; then
        systemctl --user stop openclaw-gateway 2>/dev/null || true
        systemctl --user disable openclaw-gateway 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/openclaw-gateway.service"
        log_info "已移除 systemd 用户服务"
    fi

    log_info "服务已停止"
}

# -----------------------------------------------------------
# npm 卸载
# -----------------------------------------------------------
uninstall_npm_package() {
    local version
    version=$(get_installed_version)

    if [ -z "$version" ]; then
        log_info "未检测到 openclaw（npm 全局），跳过"
        return 0
    fi

    log_info "检测到 openclaw v${version}，正在卸载..."
    npm uninstall -g openclaw 2>&1 || {
        log_warn "npm 卸载失败，尝试强制清理..."
        # 手动删除 npm 全局目录中的 openclaw
        local npm_global
        npm_global=$(get_npm_global_path)
        if [ -n "$npm_global" ] && [ -d "$npm_global/openclaw" ]; then
            rm -rf "$npm_global/openclaw"
            log_info "已手动删除 $npm_global/openclaw"
        fi
        # 删除 bin 链接
        local npm_bin
        npm_bin=$(npm bin -g 2>/dev/null || echo "")
        if [ -n "$npm_bin" ]; then
            rm -f "$npm_bin/openclaw" 2>/dev/null || true
        fi
    }

    # 验证
    if command_exists openclaw; then
        log_warn "卸载后 openclaw 命令仍存在，可能来自其他安装方式"
        log_warn "请手动检查: which openclaw"
    else
        log_info "openclaw 已从 npm 全局卸载"
    fi
}

# -----------------------------------------------------------
# 清理数据和配置
# -----------------------------------------------------------
cleanup_data() {
    echo ""
    echo -e "${YELLOW}是否清理 OpenClaw 数据和配置？${NC}"
    echo "这将删除以下目录（如存在）："
    echo "  ~/.openclaw/"
    echo "  ~/.config/openclaw/"
    echo ""
    read -r -p "确认删除? [y/N] " yn

    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        log_info "已跳过数据清理"
        return 0
    fi

    local cleaned=0

    if [ -d "$HOME/.openclaw" ]; then
        rm -rf "$HOME/.openclaw"
        log_info "已删除 ~/.openclaw/"
        cleaned=1
    fi

    if [ -d "$HOME/.config/openclaw" ]; then
        rm -rf "$HOME/.config/openclaw"
        log_info "已删除 ~/.config/openclaw/"
        cleaned=1
    fi

    # 清理 npm 缓存中的 openclaw
    local npm_cache
    npm_cache=$(npm cache ls 2>/dev/null | grep -c openclaw 2>/dev/null || echo "0")
    if [ "$npm_cache" -gt 0 ] 2>/dev/null; then
        npm cache clean --force 2>/dev/null || true
        log_info "已清理 npm 缓存"
    fi

    if [ "$cleaned" -eq 0 ]; then
        log_info "没有需要清理的数据目录"
    fi
}

# -----------------------------------------------------------
# 主流程
# -----------------------------------------------------------
main() {
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}  OpenClaw 卸载脚本${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo ""

    local version
    version=$(get_installed_version)

    if [ -n "$version" ]; then
        echo -e "  已安装版本: ${BOLD}v${version}${NC}"
    else
        echo -e "  状态: ${YELLOW}未检测到 openclaw${NC}"
    fi
    echo ""

    # 1. 停止服务
    stop_services

    # 2. npm 卸载
    uninstall_npm_package

    # 3. 清理数据
    cleanup_data

    echo ""
    log_info "卸载完成"
    echo ""
}

main "$@"
