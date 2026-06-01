#!/usr/bin/env bash
# ============================================================
# OpenClaw 跨平台自动安装/更新脚本
# 支持: macOS / Linux (Debian/Ubuntu, CentOS/RHEL/Fedora, Arch)
# 功能:
#   - 自动检测操作系统及版本
#   - 自动安装 Node.js ≥ 22（当前系统可适配的最高 LTS 版本）
#   - 配置国内 npm 镜像源（npmmirror.com）
#   - macOS 自动安装 Homebrew 并设置国内源
#   - 检测已安装版本，可更新则更新，已最新则跳过
# ============================================================

set -o pipefail

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- 配置 ----
NPM_MIRROR="https://registry.npmmirror.com"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
HOMEBREW_BREW_MIRROR="https://mirrors.ustc.edu.cn/brew.git"
HOMEBREW_CORE_MIRROR="https://mirrors.ustc.edu.cn/homebrew-core.git"
HOMEBREW_BOTTLE_MIRROR="https://mirrors.ustc.edu.cn/homebrew-bottles"
NVM_VERSION="v0.40.3"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
# 国内 nvm 安装脚本（gitee 镜像）
NVM_INSTALL_URL_CN="https://gitee.com/mirrors/nvm/raw/${NVM_VERSION}/install.sh"
# Node.js 最低要求版本（主版本号）
NODE_MIN_MAJOR=22
# Node.js 推荐主版本号（LTS）
NODE_RECOMMENDED_MAJOR=24

# ---- 工具函数 ----
log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}${BOLD}==>${NC} ${BLUE}$1${NC}"; }
log_title() { echo -e "\n${CYAN}${BOLD}============================================================${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}============================================================${NC}\n"; }

# 检查命令是否存在
command_exists() { command -v "$1" &>/dev/null; }

# 检查是否在中国大陆网络环境（通过连接速度判断）
is_cn_network() {
    # 尝试连接 npmmirror.com，如果很快响应说明在国内
    if curl -s --connect-timeout 2 --max-time 3 "https://registry.npmmirror.com/" &>/dev/null; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------
# 操作系统检测
# -----------------------------------------------------------
detect_os() {
    OS_TYPE="unknown"
    OS_NAME="unknown"
    OS_VERSION="unknown"
    PACKAGE_MANAGER="unknown"

    case "$(uname -s)" in
        Darwin)
            OS_TYPE="macos"
            OS_NAME="macOS"
            OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
            PACKAGE_MANAGER="brew"
            ;;
        Linux)
            OS_TYPE="linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_NAME="$NAME"
                OS_VERSION="$VERSION_ID"
                case "$ID" in
                    ubuntu|debian|linuxmint|pop|elementary|kali)
                        PACKAGE_MANAGER="apt"
                        ;;
                    centos|rhel|fedora|rocky|almalinux|ol|amzn)
                        PACKAGE_MANAGER="yum"
                        if command_exists dnf; then
                            PACKAGE_MANAGER="dnf"
                        fi
                        ;;
                    arch|manjaro|endeavouros)
                        PACKAGE_MANAGER="pacman"
                        ;;
                    opensuse*|sles)
                        PACKAGE_MANAGER="zypper"
                        ;;
                    alpine)
                        PACKAGE_MANAGER="apk"
                        ;;
                    *)
                        PACKAGE_MANAGER="unknown"
                        ;;
                esac
            elif [ -f /etc/redhat-release ]; then
                OS_NAME="RedHat/CentOS"
                OS_VERSION=$(rpm -q --qf "%{VERSION}" "$(rpm -q --whatprovides redhat-release)" 2>/dev/null || echo "unknown")
                PACKAGE_MANAGER="yum"
                command_exists dnf && PACKAGE_MANAGER="dnf"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS_TYPE="windows-gitbash"
            OS_NAME="Windows (Git Bash/MSYS2)"
            OS_VERSION=$(uname -r)
            PACKAGE_MANAGER="none"
            ;;
        *)
            OS_TYPE="unknown"
            OS_NAME="Unknown"
            OS_VERSION="unknown"
            PACKAGE_MANAGER="unknown"
            ;;
    esac
}

# -----------------------------------------------------------
# Node.js 版本检查
# -----------------------------------------------------------
get_node_major_version() {
    if command_exists node; then
        node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1
    else
        echo "0"
    fi
}

get_node_full_version() {
    if command_exists node; then
        node -v 2>/dev/null | sed 's/^v//'
    else
        echo "0.0.0"
    fi
}

# 版本比较：$1 >= $2 返回 0，否则返回 1
# 兼容 BSD sort (macOS) 和 GNU sort (Linux)
version_gte() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# 从 npm registry 获取最新版本
get_latest_openclaw_version() {
    local registry="$1"
    npm view openclaw version --registry="$registry" 2>/dev/null || echo ""
}

# 获取已安装的 openclaw 版本
get_installed_openclaw_version() {
    if command_exists openclaw; then
        openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        echo ""
    fi
}

# -----------------------------------------------------------
# macOS: 安装 Homebrew + 设置国内源
# -----------------------------------------------------------
setup_homebrew() {
    log_step "检查 Homebrew..."

    # 确保 brew 在当前 shell 可用（刚装完还没 reload shell 的情况）
    _ensure_brew_in_path() {
        for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
            if [ -f "$brew_path" ]; then
                eval "$("$brew_path" shellenv)"
                return 0
            fi
        done
        return 1
    }

    if command_exists brew || _ensure_brew_in_path; then
        log_info "Homebrew 已安装: $(brew --version | head -1)"
    else
        log_info "Homebrew 未安装，开始安装..."

        # 国内网络用镜像加速
        if is_cn_network; then
            log_info "检测到国内网络，使用中科大镜像..."
            export HOMEBREW_BREW_GIT_REMOTE="$HOMEBREW_BREW_MIRROR"
            export HOMEBREW_CORE_GIT_REMOTE="$HOMEBREW_CORE_MIRROR"
            export HOMEBREW_BOTTLE_DOMAIN="$HOMEBREW_BOTTLE_MIRROR"
        fi

        # 安装 Homebrew（非交互模式）
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
            if is_cn_network; then
                log_warn "官方脚本下载失败，尝试 Gitee 镜像..."
                /bin/bash -c "$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)"
            else
                log_error "Homebrew 安装失败"
                exit 1
            fi
        }

        _ensure_brew_in_path || {
            log_error "Homebrew 安装后仍不可用，请检查终端输出"
            exit 1
        }
        log_info "Homebrew 安装成功"
    fi

    # 国内网络：配置 Homebrew 镜像源 + 持久化环境变量
    if is_cn_network; then
        log_info "配置 Homebrew 国内镜像源（USTC）..."

        # git 仓库换源
        cd "$(brew --repo)" 2>/dev/null && git remote set-url origin "$HOMEBREW_BREW_MIRROR" 2>/dev/null || true
        cd "$(brew --repo homebrew/core)" 2>/dev/null && git remote set-url origin "$HOMEBREW_CORE_MIRROR" 2>/dev/null || true

        # bottles 镜像：当前 session + 持久化到 shell 配置
        export HOMEBREW_BOTTLE_DOMAIN="$HOMEBREW_BOTTLE_MIRROR"
        for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
            if [ -f "$rc" ]; then
                grep -q "HOMEBREW_BOTTLE_DOMAIN" "$rc" 2>/dev/null || \
                    echo "export HOMEBREW_BOTTLE_DOMAIN=${HOMEBREW_BOTTLE_MIRROR}" >> "$rc"
            fi
        done
        # brew API 下载也走国内镜像
        export HOMEBREW_API_DOMAIN="$HOMEBREW_BOTTLE_MIRROR/api"
        export HOMEBREW_PIP_INDEX_URL="https://mirrors.ustc.edu.cn/pypi/simple"

        log_info "Homebrew 国内源配置完成"
    fi
}

# -----------------------------------------------------------
# macOS: Node.js 版本适配 & 安装
# -----------------------------------------------------------

# 根据 macOS 版本返回系统可适配的最高 Node.js 主版本号
# Node.js 各版本对 macOS 的最低要求：
#   Node 26 → macOS 13+ (Ventura)
#   Node 24 → macOS 12+ (Monterey)
#   Node 22 → macOS 11+ (Big Sur)
get_max_node_for_macos() {
    local macos_major="$1"

    if [ "$macos_major" -lt 11 ]; then
        echo "0"   # 无可用版本
    elif [ "$macos_major" -eq 11 ]; then
        echo "22"  # Big Sur
    elif [ "$macos_major" -eq 12 ]; then
        echo "24"  # Monterey
    else
        echo "$NODE_RECOMMENDED_MAJOR"  # 13+ 用最新 LTS
    fi
}

install_nodejs_macos() {
    log_step "安装 Node.js (macOS)..."

    local node_major macos_major max_available
    node_major=$(get_node_major_version)
    macos_major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
    max_available=$(get_max_node_for_macos "$macos_major")

    # 当前版本已满足
    if [ "$node_major" -ge "$NODE_MIN_MAJOR" ]; then
        log_info "Node.js $(get_node_full_version) 已满足要求 (≥ v${NODE_MIN_MAJOR})"
        return 0
    fi

    # 系统太旧，Node.js ≥ 22 均不支持
    if [ "$max_available" -eq 0 ]; then
        log_error "macOS ${macos_major}.x 版本过旧"
        log_error "Node.js ≥ v${NODE_MIN_MAJOR} 最低要求 macOS 11 (Big Sur)"
        log_error "当前系统无法安装 OpenClaw，请升级 macOS"
        exit 1
    fi

    log_info "macOS ${macos_major}.x → 可适配最高 Node.js v${max_available}"

    # macOS 11 (Big Sur): Homebrew 已停止官方支持，走 nvm
    if [ "$macos_major" -eq 11 ]; then
        log_info "Big Sur 使用 nvm 安装 Node.js v${max_available}..."
        install_nodejs_via_nvm "$max_available"
        return $?
    fi

    # macOS 12+: 通过 Homebrew 安装
    _install_nodejs_macos_brew "$max_available"
}

# 通过 Homebrew 安装适配的 Node.js 版本
_install_nodejs_macos_brew() {
    local target_major="$1"
    local node_from_brew=false

    if ! command_exists brew; then
        setup_homebrew
    fi

    # 判断当前 node 是否来自 Homebrew
    if [ "$node_major" -gt 0 ] 2>/dev/null; then
        brew list node &>/dev/null && node_from_brew=true
    fi
    # 重新获取（可能 brew 刚装完）
    local node_major
    node_major=$(get_node_major_version)

    # 老系统装特定版本 formula，新系统装最新
    if [ "$target_major" -lt "$NODE_RECOMMENDED_MAJOR" ]; then
        local formula="node@${target_major}"
        log_info "安装 Homebrew formula: ${formula}（当前系统最高适配版本）"

        if [ "$node_from_brew" = true ]; then
            brew upgrade "$formula" 2>/dev/null || brew install "$formula"
        else
            if [ "$node_major" -gt 0 ]; then
                log_warn "当前 Node.js v${node_major} 非 Homebrew 安装，将通过 brew 安装新版本"
            fi
            brew install "$formula"
        fi

        # 版本化 formula 是 keg-only，需手动 link 才会出现在 PATH
        brew link --force --overwrite "$formula" 2>/dev/null || true
    else
        log_info "通过 Homebrew 安装 Node.js（最新稳定版）..."

        if [ "$node_from_brew" = true ]; then
            log_warn "当前 Node.js v${node_major}（brew）不满足要求，升级中..."
            brew upgrade node
        else
            if [ "$node_major" -gt 0 ]; then
                log_warn "当前 Node.js v${node_major} 非 Homebrew 安装，将通过 brew 安装新版本"
            fi
            brew install node
        fi
    fi

    # 确保 brew 的 bin 目录在 PATH 最前面（覆盖 nvm/pkg 等旧版本）
    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null || echo "")
    if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/bin" ]; then
        export PATH="$brew_prefix/bin:$PATH"
    fi

    # 验证
    node_major=$(get_node_major_version)
    if [ "$node_major" -lt "$NODE_MIN_MAJOR" ]; then
        log_error "Node.js 安装后版本仍不满足要求 (v${node_major})"
        log_error "系统中可能存在旧版 Node.js 覆盖了 Homebrew 的版本"
        log_error "请手动排查: which node && node -v"
        exit 1
    fi

    log_info "Node.js $(get_node_full_version) 安装成功"
}

# -----------------------------------------------------------
# Linux: 安装 Node.js
# -----------------------------------------------------------
install_nodejs_linux() {
    log_step "安装 Node.js (Linux)..."

    local node_major
    node_major=$(get_node_major_version)

    if [ "$node_major" -ge "$NODE_MIN_MAJOR" ]; then
        log_info "Node.js $(get_node_full_version) 已满足最低要求 (≥ v${NODE_MIN_MAJOR})"
        return 0
    fi

    log_info "当前 Node.js 版本: v${node_major}（如为 0 表示未安装）"
    log_info "将安装 Node.js v${NODE_RECOMMENDED_MAJOR} LTS..."

    # 优先尝试 nvm（用户态安装，不依赖系统包管理器版本）
    if install_nodejs_via_nvm; then
        return 0
    fi

    # nvm 失败则尝试系统包管理器 + NodeSource
    log_info "nvm 方式不可用，尝试系统包管理器安装..."

    case "$PACKAGE_MANAGER" in
        apt)
            install_nodejs_via_nodesource_apt
            ;;
        dnf|yum)
            install_nodejs_via_nodesource_rpm
            ;;
        pacman)
            log_info "使用 pacman 安装 Node.js..."
            sudo pacman -S --noconfirm nodejs npm 2>/dev/null || {
                log_error "pacman 安装失败，请手动安装 Node.js ≥ v${NODE_MIN_MAJOR}"
                exit 1
            }
            ;;
        *)
            log_error "不支持的包管理器: $PACKAGE_MANAGER"
            log_error "请手动安装 Node.js ≥ v${NODE_MIN_MAJOR}: https://nodejs.org/"
            exit 1
            ;;
    esac

    # 验证
    node_major=$(get_node_major_version)
    if [ "$node_major" -lt "$NODE_MIN_MAJOR" ]; then
        log_error "Node.js 安装后版本仍不满足要求 (v${node_major})"
        log_error "请手动安装 Node.js ≥ v${NODE_MIN_MAJOR}"
        exit 1
    fi
    log_info "Node.js $(get_node_full_version) 安装成功"
}

# 通过 nvm 安装 Node.js
# 参数: $1 - 目标主版本号（可选，默认 $NODE_RECOMMENDED_MAJOR）
install_nodejs_via_nvm() {
    local target_version="${1:-$NODE_RECOMMENDED_MAJOR}"
    log_info "尝试使用 nvm 安装 Node.js v${target_version}..."

    # 如果 nvm 已安装
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    elif [ -s "/usr/local/share/nvm/nvm.sh" ]; then
        . "/usr/local/share/nvm/nvm.sh"
    fi

    if ! command_exists nvm; then
        log_info "nvm 未安装，开始安装 nvm ${NVM_VERSION}..."
        local install_url="$NVM_INSTALL_URL"

        # 国内使用 gitee 镜像
        if is_cn_network; then
            install_url="$NVM_INSTALL_URL_CN"
            log_info "使用 Gitee 镜像安装 nvm..."
        fi

        curl -o- "$install_url" | bash 2>/dev/null || {
            log_warn "nvm 安装脚本执行失败"
            return 1
        }

        # 加载 nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    fi

    if ! command_exists nvm; then
        log_warn "nvm 安装后仍不可用"
        return 1
    fi

    # 设置 Node.js 下载镜像（国内加速）
    if is_cn_network; then
        export NVM_NODEJS_ORG_MIRROR="$NODE_MIRROR"
        log_info "设置 Node.js 下载镜像: $NODE_MIRROR"
    fi

    # 安装目标版本的 Node.js
    log_info "nvm install ${target_version}..."
    nvm install "$target_version" 2>/dev/null || {
        log_warn "nvm install ${target_version} 失败，可能当前系统不支持该版本"
        return 1
    }
    nvm use "$target_version" 2>/dev/null || true
    nvm alias default "$target_version" 2>/dev/null || true

    # 确保 node/npm 在当前 shell 中可用
    export PATH="$NVM_DIR/versions/node/$(nvm version)/bin:$PATH"

    local node_major
    node_major=$(get_node_major_version)
    if [ "$node_major" -ge "$NODE_MIN_MAJOR" ]; then
        log_info "nvm 安装 Node.js $(get_node_full_version) 成功"
        return 0
    fi
    return 1
}

# 通过 NodeSource 安装 (Debian/Ubuntu)
install_nodejs_via_nodesource_apt() {
    log_info "通过 NodeSource 安装 Node.js ${NODE_RECOMMENDED_MAJOR}.x (apt)..."

    # 更新 apt
    sudo apt-get update -qq 2>/dev/null || true

    # 安装依赖
    sudo apt-get install -y -qq curl ca-certificates gnupg 2>/dev/null || true

    # 使用 NodeSource 官方脚本
    local setup_url="https://deb.nodesource.com/setup_${NODE_RECOMMENDED_MAJOR}.x"

    if is_cn_network; then
        # 尝试 npmmirror 的 NodeSource 镜像脚本
        log_info "使用国内 Node.js 镜像..."
    fi

    curl -fsSL "$setup_url" | sudo -E bash - 2>/dev/null || {
        log_error "NodeSource setup 失败"
        log_error "请手动执行: curl -fsSL ${setup_url} | sudo -E bash -"
        exit 1
    }

    sudo apt-get install -y -qq nodejs 2>/dev/null || {
        log_error "nodejs 安装失败"
        exit 1
    }
}

# 通过 NodeSource 安装 (RHEL/CentOS/Fedora)
install_nodejs_via_nodesource_rpm() {
    log_info "通过 NodeSource 安装 Node.js ${NODE_RECOMMENDED_MAJOR}.x (rpm)..."

    local setup_url="https://rpm.nodesource.com/setup_${NODE_RECOMMENDED_MAJOR}.x"
    curl -fsSL "$setup_url" | sudo -E bash - 2>/dev/null || {
        log_error "NodeSource setup 失败"
        exit 1
    }

    if command_exists dnf; then
        sudo dnf install -y -q nodejs 2>/dev/null || {
            log_error "dnf 安装 nodejs 失败"
            exit 1
        }
    else
        sudo yum install -y -q nodejs 2>/dev/null || {
            log_error "yum 安装 nodejs 失败"
            exit 1
        }
    fi
}

# -----------------------------------------------------------
# 配置 npm 国内镜像源
# -----------------------------------------------------------
setup_npm_mirror() {
    log_step "配置 npm 镜像源..."

    if is_cn_network; then
        log_info "配置 npm registry: $NPM_MIRROR"
        npm config set registry "$NPM_MIRROR"
        log_info "npm 镜像源配置完成"
    else
        # 海外环境，确保使用官方源
        local current_registry
        current_registry=$(npm config get registry 2>/dev/null || echo "")
        if echo "$current_registry" | grep -q "npmmirror\|taobao\|mirrors"; then
            log_warn "当前 npm registry 为国内镜像 ($current_registry)"
            log_warn "检测到海外网络环境，建议使用官方源"
            read -r -p "是否切换为官方源? [y/N] " yn
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                npm config set registry "https://registry.npmjs.org/"
                log_info "已切换为官方源"
            fi
        else
            log_info "npm registry: $(npm config get registry 2>/dev/null || echo '默认官方源')"
        fi
    fi
}

# -----------------------------------------------------------
# 安装/更新 OpenClaw
# -----------------------------------------------------------
install_or_update_openclaw() {
    log_step "安装/更新 OpenClaw..."

    local registry
    registry=$(npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/")

    # 获取最新版本
    log_info "正在查询 OpenClaw 最新版本..."
    local latest_version
    latest_version=$(get_latest_openclaw_version "$registry")

    if [ -z "$latest_version" ]; then
        log_error "无法获取 OpenClaw 最新版本信息，请检查网络连接"
        log_error "npm registry: $registry"
        exit 1
    fi

    log_info "OpenClaw 最新版本: ${BOLD}v${latest_version}${NC}"

    # 检查本地已安装版本
    local installed_version
    installed_version=$(get_installed_openclaw_version)

    if [ -n "$installed_version" ]; then
        log_info "当前已安装版本: v${installed_version}"

        if [ "$installed_version" = "$latest_version" ]; then
            log_info "${GREEN}✓ 已是最新版本 v${installed_version}，无需更新${NC}"
            echo ""
            show_version_info
            return 0
        fi

        # 比较版本
        if version_gte "$installed_version" "$latest_version"; then
            log_info "${GREEN}✓ 当前版本 v${installed_version} 已是最新，无需更新${NC}"
            echo ""
            show_version_info
            return 0
        fi

        log_warn "可更新: v${installed_version} → v${latest_version}"
        read -r -p "是否更新? [Y/n] " yn
        if [[ "$yn" =~ ^[Nn]$ ]]; then
            log_info "已跳过更新"
            show_version_info
            return 0
        fi
    else
        log_info "OpenClaw 未安装，将安装最新版本 v${latest_version}"
    fi

    # 安装
    log_info "正在安装 openclaw@${latest_version}..."
    echo ""

    # 使用 npm 全局安装，用临时文件捕获退出码（兼容不同 shell 的 PIPESTATUS 行为）
    local tmp_out
    tmp_out=$(mktemp) || tmp_out="/tmp/openclaw-install-$$.log"
    npm install -g "openclaw@${latest_version}" > "$tmp_out" 2>&1
    local install_status=$?
    cat "$tmp_out"
    rm -f "$tmp_out"

    if [ "$install_status" -ne 0 ]; then
        log_error "OpenClaw 安装失败（退出码: $install_status）"
        log_error "请检查错误信息并重试"
        exit 1
    fi

    echo ""

    # 验证安装
    local new_version
    new_version=$(get_installed_openclaw_version)

    if [ -z "$new_version" ]; then
        log_error "安装后无法获取 OpenClaw 版本，安装可能未成功"
        log_error "请检查 PATH 环境变量或重新打开终端"
        exit 1
    fi

    log_info "${GREEN}✓ OpenClaw 安装成功！${NC}"
    echo ""

    if [ -n "$installed_version" ]; then
        log_info "更新完成: v${installed_version} → ${BOLD}v${new_version}${NC}"
    else
        log_info "安装完成: ${BOLD}v${new_version}${NC}"
    fi

    echo ""
    show_version_info
}

# -----------------------------------------------------------
# 显示版本信息
# -----------------------------------------------------------
show_version_info() {
    echo -e "${CYAN}${BOLD}--- 环境信息 ---${NC}"
    echo -e "  操作系统:    ${OS_NAME} ${OS_VERSION}"
    echo -e "  包管理器:    ${PACKAGE_MANAGER}"
    echo -e "  Node.js:     $(node -v 2>/dev/null || echo '未安装')"
    echo -e "  npm:         $(npm -v 2>/dev/null || echo '未安装')"
    echo -e "  npm registry: $(npm config get registry 2>/dev/null || echo '默认')"
    echo -e "  OpenClaw:    $(openclaw --version 2>/dev/null || echo '未安装')"
    echo ""
}

# -----------------------------------------------------------
# 安装后提示
# -----------------------------------------------------------
show_post_install_help() {
    log_title "安装完成！"

    echo -e "运行以下命令初始化 OpenClaw:"
    echo -e "  ${BOLD}openclaw onboard --install-daemon${NC}"
    echo ""
    echo -e "其他常用命令:"
    echo -e "  ${BOLD}openclaw --version${NC}         查看版本"
    echo -e "  ${BOLD}openclaw doctor${NC}            检查系统状态"
    echo -e "  ${BOLD}openclaw gateway status${NC}    查看网关状态"
    echo ""

    # 环境变量刷新提示
    local refreshed=false

    # Homebrew 环境
    if command_exists brew; then
        local brew_prefix
        brew_prefix=$(brew --prefix 2>/dev/null || echo "")
        if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/bin" ]; then
            # 确保当前 session 的 PATH 包含 brew
            if ! echo "$PATH" | grep -q "$brew_prefix/bin"; then
                export PATH="$brew_prefix/bin:$PATH"
                refreshed=true
            fi
        fi
    fi

    # nvm 环境
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
        refreshed=true
    fi

    # 确定 shell 配置文件
    local shell_rc=""
    case "$(basename "$SHELL" 2>/dev/null)" in
        zsh)  shell_rc="$HOME/.zshrc" ;;
        bash) shell_rc="$HOME/.bashrc" ;;
        *)    shell_rc="$HOME/.profile" ;;
    esac

    if [ "$refreshed" = true ]; then
        echo -e "${YELLOW}⚠ 当前终端已刷新环境变量${NC}"
        echo -e "${YELLOW}⚠ 打开新终端后如找不到 openclaw，请执行:${NC}"
        echo -e "  ${BOLD}source ${shell_rc}${NC}"
        echo ""
    fi

    echo -e "${CYAN}也可直接关闭并重新打开终端，环境变量即生效。${NC}"
    echo ""
}

# -----------------------------------------------------------
# 主流程
# -----------------------------------------------------------
main() {
    log_title "OpenClaw 跨平台安装脚本"

    # 1. 检测操作系统
    log_step "检测操作系统..."
    detect_os

    echo -e "  操作系统:    ${BOLD}${OS_NAME}${NC}"
    echo -e "  版本:        ${OS_VERSION}"
    echo -e "  包管理器:    ${PACKAGE_MANAGER}"
    echo ""

    if [ "$OS_TYPE" = "unknown" ]; then
        log_error "无法识别的操作系统: $(uname -s)"
        log_error "支持的平台: macOS, Linux (Debian/Ubuntu, CentOS/RHEL/Fedora, Arch)"
        exit 1
    fi

    if [ "$OS_TYPE" = "windows-gitbash" ]; then
        log_warn "检测到 Windows Git Bash/MSYS2 环境"
        log_warn "建议在 Windows 上使用 WSL2 运行本脚本，或使用 install-openclaw.ps1"
        read -r -p "是否继续在 Git Bash 中运行? [y/N] " yn
        if [[ ! "$yn" =~ ^[Yy]$ ]]; then
            log_info "已退出，请使用 WSL2 或 PowerShell 脚本"
            exit 0
        fi
    fi

    # 2. 安装 Node.js（按平台分发）
    case "$OS_TYPE" in
        macos)
            install_nodejs_macos
            ;;
        linux)
            install_nodejs_linux
            ;;
        windows-gitbash)
            # Git Bash 环境: 尝试使用 nvm
            install_nodejs_via_nvm || {
                log_error "Git Bash 下安装 Node.js 失败"
                log_error "请在 Windows 上使用 install-openclaw.ps1 或安装 WSL2"
                exit 1
            }
            ;;
    esac

    # 确保 npm 可用
    if ! command_exists npm; then
        log_error "npm 不可用，Node.js 安装可能不完整"
        exit 1
    fi

    # 3. 配置 npm 国内镜像
    setup_npm_mirror

    # 4. 安装/更新 OpenClaw
    install_or_update_openclaw

    # 5. 完成提示
    show_post_install_help
}

# 运行主函数
main "$@"
