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
log_step()  { echo -e "\n${BOLD}--- $1 ---${NC}"; }

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

get_npm_global_path() {
    npm root -g 2>/dev/null || echo ""
}

# -----------------------------------------------------------
# 第一步：停止所有 OpenClaw 进程（先于 npm 卸载执行）
# -----------------------------------------------------------
kill_all_processes() {
    log_step "停止 OpenClaw 进程"

    local killed=0

    # 1) 通过 CLI 停止 gateway（此时 openclaw 命令还在）
    if command_exists openclaw; then
        log_info "调用 openclaw gateway stop ..."
        openclaw gateway stop 2>/dev/null || true
        sleep 1
    fi

    # 2) pkill 所有相关进程
    local patterns=("openclaw" "clawdbot" "moltbot")
    for pat in "${patterns[@]}"; do
        if pgrep -f "$pat" &>/dev/null; then
            log_info "终止进程: $pat"
            pkill -f "$pat" 2>/dev/null || true
            killed=1
        fi
    done

    # 等待进程退出
    sleep 1

    # 3) 强制杀掉残留（用之前用过的名称）
    for pat in "${patterns[@]}"; do
        if pgrep -f "$pat" &>/dev/null; then
            log_warn "进程残留，强制终止: $pat"
            pkill -9 -f "$pat" 2>/dev/null || true
        fi
    done

    if [ "$killed" -eq 0 ]; then
        log_info "没有运行中的 OpenClaw 进程"
    fi
}

# -----------------------------------------------------------
# 第二步：卸载系统服务（launchd / systemd）
# -----------------------------------------------------------
remove_system_services() {
    log_step "移除系统服务"

    # --- macOS LaunchAgent ---
    # openclaw 的 LaunchAgent 可能叫不同名字，搜索所有可能的 plist
    if [ -d "$HOME/Library/LaunchAgents" ]; then
        local plists
        plists=$(find "$HOME/Library/LaunchAgents" -maxdepth 1 -name '*openclaw*' -o -name '*clawdbot*' -o -name '*moltbot*' 2>/dev/null)
        if [ -n "$plists" ]; then
            while IFS= read -r plist; do
                log_info "卸载 LaunchAgent: $(basename "$plist")"
                launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || \
                    launchctl unload "$plist" 2>/dev/null || true
                rm -f "$plist"
                log_info "已删除: $plist"
            done <<< "$plists"
        else
            log_info "未找到 openclaw 相关的 LaunchAgent"
        fi
    fi

    # 也检查 /Library/LaunchDaemons（系统级）
    for dir in "/Library/LaunchDaemons" "/Library/LaunchAgents"; do
        if [ -d "$dir" ]; then
            local sys_plists
            sys_plists=$(find "$dir" -maxdepth 1 -name '*openclaw*' -o -name '*clawdbot*' 2>/dev/null)
            if [ -n "$sys_plists" ]; then
                while IFS= read -r plist; do
                    log_warn "发现系统级服务: $plist"
                    sudo launchctl bootout system "$plist" 2>/dev/null || \
                        sudo launchctl unload "$plist" 2>/dev/null || true
                    sudo rm -f "$plist"
                done <<< "$sys_plists"
            fi
        fi
    done

    # --- Linux systemd ---
    if command_exists systemctl; then
        for name in openclaw-gateway openclaw clawdbot moltbot; do
            if systemctl --user is-enabled "$name" &>/dev/null 2>&1; then
                systemctl --user stop "$name" 2>/dev/null || true
                systemctl --user disable "$name" 2>/dev/null || true
                log_info "已停止 systemd 用户服务: $name"
            fi
            rm -f "$HOME/.config/systemd/user/${name}.service" 2>/dev/null
        done
    fi
}

# -----------------------------------------------------------
# 第三步：npm 卸载
# -----------------------------------------------------------
uninstall_npm_package() {
    log_step "npm 卸载"

    local version
    version=$(get_installed_version)

    if [ -z "$version" ]; then
        log_info "openclaw 未通过 npm 安装，跳过"
        return 0
    fi

    log_info "检测到 openclaw v${version}，正在卸载..."
    npm uninstall -g openclaw 2>&1 || {
        log_warn "npm 卸载失败，手动清理残留..."
        local npm_global
        npm_global=$(get_npm_global_path)
        if [ -n "$npm_global" ] && [ -d "$npm_global/openclaw" ]; then
            rm -rf "$npm_global/openclaw"
            log_info "已删除 $npm_global/openclaw"
        fi
        local npm_bin
        npm_bin=$(npm bin -g 2>/dev/null || echo "")
        if [ -n "$npm_bin" ]; then
            rm -f "$npm_bin/openclaw" "$npm_bin/clawdbot" "$npm_bin/moltbot" 2>/dev/null || true
        fi
    }

    # 验证
    hash -r 2>/dev/null || true  # 刷新 bash 命令缓存
    if command_exists openclaw; then
        log_warn "卸载后 openclaw 命令仍存在: $(which openclaw 2>/dev/null)"
        log_warn "请手动删除该文件"
    else
        log_info "openclaw 已从 npm 全局卸载"
    fi
}

# -----------------------------------------------------------
# 第四步：清理数据和配置
# -----------------------------------------------------------
cleanup_data() {
    log_step "清理数据"

    echo ""
    echo -e "  以下目录将被删除（如存在）："
    echo -e "    ~/.openclaw/"
    echo -e "    ~/.config/openclaw/"
    echo -e "    ~/.clawdbot/"
    echo -e "    ~/.moltbot/"
    echo ""
    read -r -p "  确认删除? [y/N] " yn

    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        log_info "已跳过数据清理"
        return 0
    fi

    local cleaned=0
    for dir in "$HOME/.openclaw" "$HOME/.config/openclaw" "$HOME/.clawdbot" "$HOME/.moltbot"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            log_info "已删除 $dir"
            cleaned=1
        fi
    done

    # npm 缓存
    npm cache clean --force 2>/dev/null || true

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
        echo -e "  状态: ${YELLOW}openclaw 命令未找到${NC}（可能已卸载，继续清理残留）"
    fi
    echo ""

    # 执行顺序很关键：先停服务/杀进程，再卸载包，最后清数据
    kill_all_processes
    remove_system_services
    uninstall_npm_package
    cleanup_data

    echo ""
    log_info "卸载完成"
    echo ""
}

main "$@"
