#!/bin/bash
#=============================================================================
# ImmortalWrt 编译环境一键搭建与编译脚本（虚拟化环境优化）
# 功能：环境检测/依赖安装/源码克隆/feeds更新/配置/编译/多线程优化
# 支持：Ubuntu / Debian（推荐 Debian 12 / Ubuntu 22.04+）
# 环境：虚拟机/云服务器/WSL2
# 用法：chmod +x immortalwrt_build.sh && ./immortalwrt_build.sh
#=============================================================================

set -e

#-------------------- 颜色定义 --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

#-------------------- 辅助函数 --------------------
info()  { echo -e "${GREEN}[信息]${NC} $*"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
error() { echo -e "${RED}[错误]${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
fail()  { echo -e "${RED}  ✗${NC} $*"; }
sep()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
sep_s() { echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"; }

#-------------------- 全局变量 --------------------
BUILD_USER="${SUDO_USER:-$(whoami)}"
BUILD_HOME=$(eval echo "~${BUILD_USER}")
SOURCE_DIR="${BUILD_HOME}/immortalwrt"
WORK_DIR="${BUILD_HOME}/immortalwrt-build"
CONFIG_BACKUP_DIR="${BUILD_HOME}/.immortalwrt_configs"
LOG_FILE="${BUILD_HOME}/immortalwrt_build.log"
BUILD_THREAD=""
LATEST_BRANCH="master"

#-------------------- 获取系统信息 --------------------
get_system_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_NAME="${PRETTY_NAME}"
        OS_VERSION="${VERSION_ID}"
    else
        OS_ID="unknown"
        OS_NAME="未知系统"
    fi

    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    TOTAL_MEM=$(free -g 2>/dev/null | awk '/Mem:/{print $2}')
    TOTAL_MEM="${TOTAL_MEM:-4}"
    DISK_AVAIL=$(df -BG "${BUILD_HOME}" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    DISK_AVAIL="${DISK_AVAIL:-50}"

    # 检测虚拟化环境
    VIRT_TYPE=""
    if [[ -f /proc/1/environ ]]; then
        if grep -qa "WSL" /proc/1/environ 2>/dev/null; then
            VIRT_TYPE="WSL2"
        fi
    fi
    if [[ -z "$VIRT_TYPE" ]] && command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "")
    fi
    [[ -z "$VIRT_TYPE" ]] && VIRT_TYPE="物理机/未知"
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    get_system_info

    sep
    echo -e "${BOLD}     ImmortalWrt 编译环境（虚拟化优化）${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}系统  ：${NC}${OS_NAME}"
    echo -e "  ${BLUE}架构  ：${NC}$(uname -m)  |  ${BLUE}CPU：${NC}${CPU_CORES}核  |  ${BLUE}内存：${NC}${TOTAL_MEM}GB  |  ${BLUE}磁盘：${NC}${DISK_AVAIL}GB"
    echo -e "  ${BLUE}虚拟化：${NC}${VIRT_TYPE}"
    echo -e "  ${BLUE}用户  ：${NC}${BUILD_USER}"
    echo -e "  ${BLUE}源码  ：${NC}${SOURCE_DIR}"
    echo ""

    # 检测编译环境状态
    echo -e "  ${BOLD}环境状态：${NC}"
    echo -n "  依赖包    : "
    if dpkg -l build-essential &>/dev/null 2>&1; then
        echo -e "${GREEN}已安装${NC}"
    else
        echo -e "${YELLOW}未安装${NC}"
    fi

    echo -n "  源码      : "
    if [[ -d "$SOURCE_DIR/.git" ]]; then
        local branch=$(cd "$SOURCE_DIR" 2>/dev/null && git branch --show-current 2>/dev/null || echo "unknown")
        echo -e "${GREEN}已克隆（${branch}）${NC}"
    else
        echo -e "${YELLOW}未克隆${NC}"
    fi

    echo -n "  配置文件  : "
    if [[ -f "$SOURCE_DIR/.config" ]]; then
        echo -e "${GREEN}已配置${NC}"
    else
        echo -e "${YELLOW}未配置${NC}"
    fi

    echo -n "  编译产物  : "
    if ls "$SOURCE_DIR/bin/targets/"*/*/*.img 2>/dev/null | head -1 &>/dev/null; then
        echo -e "${GREEN}已有固件${NC}"
    else
        echo -e "${YELLOW}无${NC}"
    fi

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【环境准备】${NC}"
    echo -e "  ${CYAN} 1)${NC} 一键搭建编译环境（安装全部依赖）"
    echo -e "  ${CYAN} 2)${NC} 检测系统环境是否满足编译要求"
    echo -e "  ${CYAN} 3)${NC} 优化虚拟化环境（交换分区/内存/网络）"
    echo ""

    echo -e "  ${CYAN}【源码管理】${NC}"
    echo -e "  ${CYAN} 4)${NC} 克隆 ImmortalWrt 源码"
    echo -e "  ${CYAN} 5)${NC} 更新源码（git pull）"
    echo -e "  ${CYAN} 6)${NC} 切换分支/版本"
    echo -e "  ${CYAN} 7)${NC} 添加额外 feeds 源"
    echo ""

    echo -e "  ${CYAN}【配置管理】${NC}"
    echo -e "  ${CYAN} 8)${NC} 更新并安装 feeds"
    echo -e "  ${CYAN} 9)${NC} 打开菜单配置（make menuconfig）"
    echo -e " ${CYAN}10)${NC} 加载预设配置（x86_64/通用路由器等）"
    echo -e " ${CYAN}11)${NC} 备份当前配置"
    echo -e " ${CYAN}12)${NC} 恢复配置"
    echo ""
    echo -e "  ${MAGENTA}【DIY 固件定制】${NC}"
    echo -e " ${CYAN}21)${NC} DIY 基础设置（中文/密码/IP/WiFi/主机名/DNS/时区）"
    echo -e " ${CYAN}22)${NC} DIY 高级设置（账号/WAN/Led/内核/分区/防火墙等）"
    echo -e " ${CYAN}23)${NC} DIY 预设方案（快速模板一键应用）"
    echo -e " ${CYAN}24)${NC} DIY 一键应用到源码"
    echo -e " ${CYAN}25)${NC} 查看/导出/导入 DIY 配置"
    echo ""

    echo -e "  ${CYAN}【编译管理】${NC}"
    echo -e " ${CYAN}13)${NC} 开始编译（自动检测线程数）"
    echo -e " ${CYAN}14)${NC} 仅编译工具链（首次编译推荐）"
    echo -e " ${CYAN}15)${NC} 后台编译（nohup，可断开 SSH）"
    echo -e " ${CYAN}16)${NC} 清理编译（clean/dirclean/distclean）"
    echo -e " ${CYAN}17)${NC} 查看编译日志"
    echo -e " ${CYAN}18)${NC} 查看编译产物"
    echo ""

    echo -e "  ${CYAN}【辅助】${NC}"
    echo -e " ${CYAN}19)${NC} 下载固件到本地（sz 命令）"
    echo -e " ${CYAN}20)${NC} 常见问题与解决方案"
    echo -e " ${CYAN} 0)${NC} 退出"
    echo ""
    sep
    echo -n "请输入选项: "
}

#-------------------- 权限检查 --------------------
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        warn "ImmortalWrt 编译不应使用 root 用户"
        echo -e "  ${YELLOW}建议使用普通用户运行此脚本${NC}"
        echo -e "  ${YELLOW}依赖安装部分会自动使用 sudo${NC}"
        echo ""
        echo -n "  是否继续？(Y/n): "
        read -r confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
    fi
}

#-------------------- 功能 1：一键搭建编译环境 --------------------
setup_build_env() {
    sep
    echo -e "${BOLD}          一键搭建 ImmortalWrt 编译环境${NC}"
    sep
    echo ""

    # 检测系统
    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop)
            ok "支持的系统: ${OS_NAME}"
            ;;
        *)
            warn "不推荐的系统: ${OS_NAME}"
            echo -e "  ${YELLOW}官方推荐 Debian 11+ 或 Ubuntu 20.04+${NC}"
            echo -n "  是否继续？(Y/n): "
            read -r confirm
            [[ "$confirm" =~ ^[Nn]$ ]] && return
            ;;
    esac

    echo ""
    echo -e "  ${BOLD}系统资源：${NC}"
    echo -e "  ${BLUE}CPU 核心：${NC}${CPU_CORES} 核"
    echo -e "  ${BLUE}内存    ：${NC}${TOTAL_MEM} GB（推荐 4GB+）"
    echo -e "  ${BLUE}磁盘    ：${NC}${DISK_AVAIL} GB（推荐 25GB+）"
    echo -e "  ${BLUE}虚拟化  ：${NC}${VIRT_TYPE}"
    echo ""

    # 检查资源是否足够
    local warnings=0
    if [[ "$TOTAL_MEM" -lt 4 ]]; then
        warn "内存不足 4GB，编译可能失败或非常慢"
        warnings=$((warnings + 1))
    fi
    if [[ "$DISK_AVAIL" -lt 25 ]]; then
        warn "磁盘空间不足 25GB，编译可能失败"
        warnings=$((warnings + 1))
    fi

    if [[ $warnings -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}建议先通过菜单 3 优化虚拟化环境${NC}"
        echo -n "  是否继续安装依赖？(Y/n): "
        read -r confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && return
    fi

    echo ""
    info "更新系统软件包..."
    sudo apt-get update -y 2>/dev/null
    sudo apt-get full-upgrade -y 2>/dev/null

    echo ""
    info "安装编译依赖包..."

    # 官方完整依赖列表
    sudo apt-get install -y \
        ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
        bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext \
        gcc-multilib g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 \
        libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev \
        libncurses-dev libpython3-dev libreadline-dev libssl-dev libtool libyaml-dev libz-dev \
        lld llvm lrzsz mkisofs msmtp nano ninja-build p7zip p7zip-full patch pkgconf python3 \
        python3-pip python3-ply python3-docutils python3-pyelftools qemu-utils re2c rsync scons \
        squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd \
        zlib1g-dev zstd 2>/dev/null

    ok "依赖包安装完成"

    # 配置 git
    echo ""
    info "配置 Git..."
    git config --global user.email "build@immortalwrt.local" 2>/dev/null || true
    git config --global user.name "ImmortalWrt Builder" 2>/dev/null || true
    git config --global advice.detachedHead false 2>/dev/null || true

    # WSL2 特殊处理
    if [[ "$VIRT_TYPE" == "WSL2" ]]; then
        echo ""
        info "检测到 WSL2 环境，进行特殊配置..."
        setup_wsl2
    fi

    # 配置 swap
    if [[ "$TOTAL_MEM" -lt 4 ]]; then
        echo ""
        warn "内存不足 4GB，自动创建交换分区..."
        setup_swap
    fi

    # 配置并发下载
    echo ""
    info "优化编译参数..."

    # 设置 make 并发数（CPU 核心数 + 1）
    local threads=$((CPU_CORES + 1))
    echo "export MAKEFLAGS=-j${threads}" >> "${BUILD_HOME}/.bashrc" 2>/dev/null || true

    ok "编译环境搭建完成"
    echo ""
    echo -e "  ${GREEN}${BOLD}● 编译环境已就绪！${NC}"
    echo -e "  ${BLUE}建议编译线程数：${NC}${threads}"
    echo -e "  ${YELLOW}下一步：使用菜单 4 克隆源码${NC}"

    sep
}

#-------------------- WSL2 特殊配置 --------------------
setup_wsl2() {
    warn "WSL2 环境优化..."

    # 移除 Windows 路径（编译要求）
    local win_path=$(echo "$PATH" | tr ':' '\n' | grep -i "mnt/c" | head -1)
    if [[ -n "$win_path" ]]; then
        info "检测到 Windows 路径在 PATH 中，可能导致编译失败"
        echo -e "  ${YELLOW}建议编辑 ~/.bashrc 添加以下内容移除 Windows 路径：${NC}"
        echo -e "  ${CYAN}export PATH=\$(echo \$PATH | tr ':' '\n' | grep -v mnt | paste -sd':')${NC}"
        echo ""

        echo -n "  是否自动配置？(Y/n): "
        read -r wsl_confirm
        if [[ ! "$wsl_confirm" =~ ^[Nn]$ ]]; then
            # 添加到 .bashrc
            if ! grep -q "Remove Windows path" "${BUILD_HOME}/.bashrc" 2>/dev/null; then
                cat >> "${BUILD_HOME}/.bashrc" <<'EOF'

# Remove Windows path for ImmortalWrt build
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/mnt/c' | paste -sd':')
EOF
                ok "已添加路径过滤到 ~/.bashrc"
                warn "请重新打开终端或执行 source ~/.bashrc 生效"
            fi
        fi
    fi

    # WSL2 大小写敏感设置
    local fs_type=$(stat -f -c "%T" "${BUILD_HOME}" 2>/dev/null || echo "unknown")
    if [[ "$fs_type" == "drvfs" ]] || [[ "$fs_type" == "9p" ]]; then
        warn "WSL2 文件系统可能不区分大小写"
        echo -e "  ${YELLOW}建议将源码克隆到 ext4 文件系统中（如 /home/）${NC}"
    fi
}

#-------------------- 功能 2：检测系统环境 --------------------
check_system() {
    sep
    echo -e "${BOLD}          系统环境检测${NC}"
    sep
    echo ""

    local pass=0
    local warn_count=0

    # 操作系统
    echo -e "  ${BOLD}--- 操作系统 ---${NC}"
    case "$OS_ID" in
        ubuntu|debian)
            ok "系统: ${OS_NAME}"
            pass=$((pass + 1))
            ;;
        *)
            fail "不推荐的系统: ${OS_NAME}（推荐 Debian/Ubuntu）"
            warn_count=$((warn_count + 1))
            ;;
    esac

    # CPU
    echo ""
    echo -e "  ${BOLD}--- CPU ---${NC}"
    if [[ "$CPU_CORES" -ge 2 ]]; then
        ok "CPU 核心: ${CPU_CORES} 核（满足 2 核最低要求）"
        pass=$((pass + 1))
    else
        fail "CPU 核心不足: ${CPU_CORES} 核（需要 2 核以上）"
        warn_count=$((warn_count + 1))
    fi

    # 内存
    echo ""
    echo -e "  ${BOLD}--- 内存 ---${NC}"
    if [[ "$TOTAL_MEM" -ge 4 ]]; then
        ok "内存: ${TOTAL_MEM} GB（满足 4GB 最低要求）"
        pass=$((pass + 1))
    elif [[ "$TOTAL_MEM" -ge 2 ]]; then
        warn "内存: ${TOTAL_MEM} GB（勉强够用，建议添加 swap）"
        warn_count=$((warn_count + 1))
    else
        fail "内存不足: ${TOTAL_MEM} GB（需要 4GB 以上）"
        warn_count=$((warn_count + 1))
    fi

    # 磁盘
    echo ""
    echo -e "  ${BOLD}--- 磁盘 ---${NC}"
    if [[ "$DISK_AVAIL" -ge 25 ]]; then
        ok "磁盘空间: ${DISK_AVAIL} GB（满足 25GB 最低要求）"
        pass=$((pass + 1))
    else
        fail "磁盘空间不足: ${DISK_AVAIL} GB（需要 25GB 以上）"
        warn_count=$((warn_count + 1))
    fi

    # 关键依赖
    echo ""
    echo -e "  ${BOLD}--- 编译依赖 ---${NC}"
    local deps=("build-essential" "gcc" "g++" "make" "cmake" "git" "python3" "wget" "curl" "flex" "bison" "libssl-dev" "libncurses-dev")
    local dep_missing=0
    for dep in "${deps[@]}"; do
        if dpkg -l "$dep" &>/dev/null 2>&1; then
            ok "$dep"
        else
            fail "$dep 未安装"
            dep_missing=$((dep_missing + 1))
        fi
    done

    if [[ $dep_missing -eq 0 ]]; then
        pass=$((pass + 1))
    else
        warn_count=$((warn_count + 1))
    fi

    # 网络
    echo ""
    echo -e "  ${BOLD}--- 网络 ---${NC}"
    if ping -c 1 -W 3 github.com &>/dev/null 2>&1; then
        ok "GitHub 连通"
        pass=$((pass + 1))
    else
        warn "GitHub 不通（可能需要代理或镜像）"
        warn_count=$((warn_count + 1))
    fi

    # 虚拟化
    echo ""
    echo -e "  ${BOLD}--- 虚拟化环境 ---${NC}"
    echo -e "  ${CYAN}类型: ${VIRT_TYPE}${NC}"

    if [[ "$VIRT_TYPE" == "WSL2" ]]; then
        warn "WSL2 环境需要额外配置（PATH 过滤）"
        warn_count=$((warn_count + 1))
    fi

    # 总结
    echo ""
    sep_s
    echo ""
    if [[ $warn_count -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}● 所有检测项通过，可以开始编译！${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}● 有 ${warn_count} 个警告项需要处理${NC}"
        echo -e "  ${YELLOW}建议使用菜单 1 一键安装环境${NC}"
    fi

    sep
}

#-------------------- 功能 3：优化虚拟化环境 --------------------
optimize_virt_env() {
    sep
    echo -e "${BOLD}          虚拟化环境优化${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}当前环境：${NC}${VIRT_TYPE}"
    echo -e "  ${BLUE}CPU：${NC}${CPU_CORES}核  ${BLUE}内存：${NC}${TOTAL_MEM}GB  ${BLUE}磁盘：${NC}${DISK_AVAIL}GB"
    echo ""

    # Swap 优化
    local swap_size=$(free -g 2>/dev/null | awk '/Swap:/{print $2}')
    swap_size="${swap_size:-0}"

    echo -e "  ${BOLD}1. 交换分区（Swap）${NC}"
    if [[ "$TOTAL_MEM" -lt 4 ]] || [[ "$swap_size" -lt 2 ]]; then
        echo -e "  ${YELLOW}内存不足或无 swap，建议创建${NC}"
        echo -n "  是否创建/扩大 swap？(Y/n): "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
            setup_swap
        fi
    else
        ok "Swap 已配置: ${swap_size}GB"
    fi

    echo ""

    # DNS 优化
    echo -e "  ${BOLD}2. DNS 配置${NC}"
    echo -e "  ${YELLOW}编译需要大量下载，好的 DNS 可提高速度${NC}"
    echo -n "  是否优化 DNS？(Y/n): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        sudo cp /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%Y%m%d)" 2>/dev/null
        sudo tee /etc/resolv.conf > /dev/null <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
EOF
        ok "DNS 已优化"
    fi

    echo ""

    # Git 代理
    echo -e "  ${BOLD}3. Git 加速${NC}"
    echo -e "  ${YELLOW}如果 GitHub 访问慢，可配置代理或镜像${NC}"
    echo -n "  是否配置 Git 加速？(y/N): "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "  ${CYAN} 1)${NC} 使用 ghproxy 加速"
        echo -e "  ${CYAN} 2)${NC} 使用 HTTP 代理"
        echo -e "  ${CYAN} 3)${NC} 使用 SOCKS5 代理"
        echo -n "  请选择: "
        read -r proxy_choice

        case "$proxy_choice" in
            1)
                git config --global url."https://ghp.ci/https://github.com/".insteadOf "https://github.com/"
                ok "已配置 ghproxy 加速"
                ;;
            2)
                echo -n "  代理地址（如 http://127.0.0.1:7890）: "
                read -r proxy_addr
                git config --global http.proxy "$proxy_addr"
                git config --global https.proxy "$proxy_addr"
                ok "已配置 HTTP 代理"
                ;;
            3)
                echo -n "  SOCKS5 地址（如 socks5://127.0.0.1:1080）: "
                read -r socks_addr
                git config --global http.proxy "$socks_addr"
                git config --global https.proxy "$socks_addr"
                ok "已配置 SOCKS5 代理"
                ;;
        esac
    fi

    echo ""

    # 编译缓存
    echo -e "  ${BOLD}4. 编译缓存（ccache）${NC}"
    if ! command -v ccache &>/dev/null; then
        sudo apt-get install -y ccache 2>/dev/null
    fi
    if command -v ccache &>/dev/null; then
        ccache -M 10G 2>/dev/null
        ok "ccache 缓存已设置为 10GB"
    fi

    echo ""

    # 文件描述符限制
    echo -e "  ${BOLD}5. 文件描述符限制${NC}"
    local nofile=$(ulimit -n)
    if [[ "$nofile" -lt 65535 ]]; then
        echo -e "  ${YELLOW}当前限制: ${nofile}，建议提升到 65535${NC}"
        echo -n "  是否提升？(Y/n): "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
            if ! grep -q "immortalwrt build" /etc/security/limits.conf 2>/dev/null; then
                sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# immortalwrt build
* soft nofile 65535
* hard nofile 65535
EOF
            fi
            ulimit -n 65535 2>/dev/null || true
            ok "文件描述符限制已提升"
            warn "需要重新登录生效"
        fi
    else
        ok "文件描述符限制: ${nofile}"
    fi

    echo ""
    ok "虚拟化环境优化完成"

    sep
}

#-------------------- 创建 Swap --------------------
setup_swap() {
    local swap_size_mb=4096
    if [[ "$TOTAL_MEM" -le 2 ]]; then
        swap_size_mb=8192
    fi

    local swap_file="/swapfile_immortalwrt"
    info "创建 ${swap_size_mb}MB 交换文件..."

    sudo fallocate -l "${swap_size_mb}M" "$swap_file" 2>/dev/null || sudo dd if=/dev/zero of="$swap_file" bs=1M count="$swap_size_mb"
    sudo chmod 600 "$swap_file"
    sudo mkswap "$swap_file"
    sudo swapon "$swap_file"

    # 添加到 fstab
    if ! grep -q "$swap_file" /etc/fstab 2>/dev/null; then
        echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi

    # 降低 swappiness
    sudo sysctl vm.swappiness=10 2>/dev/null
    if ! grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null
    fi

    ok "Swap 已创建: ${swap_size_mb}MB"
}

#-------------------- 功能 4：克隆源码 --------------------
clone_source() {
    sep
    echo -e "${BOLD}          克隆 ImmortalWrt 源码${NC}"
    sep
    echo ""

    if [[ -d "$SOURCE_DIR/.git" ]]; then
        warn "源码目录已存在: ${SOURCE_DIR}"
        echo -n "  是否重新克隆？（会删除现有源码）(y/N): "
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
        rm -rf "$SOURCE_DIR"
    fi

    echo -e "  ${BOLD}选择分支/版本：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} master ${GREEN}（最新开发版，推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} openwrt-24.10 ${YELLOW}（最新稳定版分支）${NC}"
    echo -e "  ${CYAN} 3)${NC} openwrt-23.05 ${YELLOW}（旧稳定版分支）${NC}"
    echo -e "  ${CYAN} 4)${NC} 自定义分支/tag"
    echo ""
    echo -n "请选择 [1-4]（默认 1）: "
    read -r branch_choice

    local branch="master"
    case "$branch_choice" in
        2) branch="openwrt-24.10" ;;
        3) branch="openwrt-23.05" ;;
        4)
            echo -n "  输入分支/tag 名称: "
            read -r branch
            ;;
    esac

    LATEST_BRANCH="$branch"

    echo ""
    echo -e "  ${BOLD}克隆选项：${NC}"
    echo -n "  使用浅克隆（--filter=blob:none，节省空间）？(Y/n): "
    read -r shallow
    local clone_opts="--single-branch"
    if [[ ! "$shallow" =~ ^[Nn]$ ]]; then
        clone_opts="${clone_opts} --filter=blob:none"
    fi

    echo ""
    info "开始克隆 ImmortalWrt 源码（分支: ${branch}）..."
    echo -e "  ${YELLOW}这可能需要 10-30 分钟，取决于网络速度${NC}"
    echo ""

    cd "${BUILD_HOME}"

    if git clone -b "$branch" $clone_opts "https://github.com/immortalwrt/immortalwrt.git" "$SOURCE_DIR"; then
        ok "源码克隆成功"
        echo ""
        echo -e "  ${BLUE}源码路径：${NC}${SOURCE_DIR}"
        echo -e "  ${BLUE}分支    ：${NC}${branch}"

        # 显示源码大小
        local size=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1)
        echo -e "  ${BLUE}大小    ：${NC}${size}"

        echo ""
        echo -e "  ${YELLOW}下一步：使用菜单 8 更新并安装 feeds${NC}"
    else
        error "源码克隆失败"
        echo -e "  ${YELLOW}可能的原因：${NC}"
        echo -e "  1. 网络问题，请检查 GitHub 连通性"
        echo -e "  2. 分支名错误"
        echo -e "  3. 磁盘空间不足"
        echo -e "  ${YELLOW}建议使用菜单 3 配置 Git 加速${NC}"
    fi

    sep
}

#-------------------- 功能 5：更新源码 --------------------
update_source() {
    sep
    echo -e "${BOLD}          更新 ImmortalWrt 源码${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR/.git" ]]; then
        error "源码目录不存在，请先克隆源码"
        return
    fi

    cd "$SOURCE_DIR"

    local current_branch=$(git branch --show-current 2>/dev/null)
    echo -e "  ${BLUE}当前分支：${NC}${current_branch}"
    echo ""

    info "拉取最新代码..."
    git pull --all 2>/dev/null || git pull origin "$current_branch" 2>/dev/null

    local new_commit=$(git log -1 --oneline 2>/dev/null)
    ok "更新完成"
    echo -e "  ${BLUE}最新提交：${NC}${new_commit}"

    sep
}

#-------------------- 功能 6：切换分支 --------------------
switch_branch() {
    sep
    echo -e "${BOLD}          切换分支/版本${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR/.git" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    local current_branch=$(git branch --show-current 2>/dev/null)
    echo -e "  ${BLUE}当前分支：${NC}${current_branch}"
    echo ""

    echo -e "  ${BOLD}可用远程分支：${NC}"
    echo ""
    git branch -r 2>/dev/null | grep -E "origin/(master|openwrt-)" | head -20 | while read -r b; do
        echo -e "    ${CYAN}${b}${NC}"
    done
    echo ""

    echo -n "  输入要切换的分支/tag 名称: "
    read -r new_branch

    if [[ -z "$new_branch" ]]; then
        info "已取消"
        return
    fi

    info "切换到 ${new_branch}..."
    git fetch origin 2>/dev/null
    if git checkout "$new_branch" 2>/dev/null; then
        git pull origin "$new_branch" 2>/dev/null || true
        ok "已切换到 ${new_branch}"
        warn "切换分支后请重新执行 feeds 更新和安装"
    else
        error "切换失败，请检查分支名"
    fi

    sep
}

#-------------------- 功能 7：添加额外 feeds --------------------
add_extra_feeds() {
    sep
    echo -e "${BOLD}          添加额外 feeds 源${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR/.git" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    echo -e "  ${BOLD}常用额外 feeds：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} passwall     ${GREEN}（科学上网插件）${NC}"
    echo -e "  ${CYAN} 2)${NC} passwall2    ${GREEN}（passwall v2）${NC}"
    echo -e "  ${CYAN} 3)${NC} ssr-plus     ${GREEN}（SSR Plus+）${NC}"
    echo -e "  ${CYAN} 4)${NC} openclash    ${GREEN}（OpenClash）${NC}"
    echo -e "  ${CYAN} 5)${NC} luci-theme-argon ${GREEN}（Argon 主题）${NC}"
    echo -e "  ${CYAN} 6)${NC} istore       ${GREEN}（iStore 应用商店）${NC}"
    echo -e "  ${CYAN} 7)${NC} homeproxy    ${GREEN}（HomeProxy）${NC}"
    echo -e "  ${CYAN} 8)${NC} 自定义 feed"
    echo -e "  ${CYAN} 9)${NC} 清除所有额外 feeds"
    echo ""
    echo -n "请选择（可多选，用空格分隔）: "
    read -r feed_choices

    local feeds_file="${SOURCE_DIR}/feeds.conf.default"
    local custom_feeds_file="${SOURCE_DIR}/feeds.conf"

    for choice in $feed_choices; do
        local feed_line=""
        case "$choice" in
            1) feed_line="src-git passwall https://github.com/xiaorouji/openwrt-passwall.git;main" ;;
            2) feed_line="src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git;main" ;;
            3) feed_line="src-git helloworld https://github.com/fw876/helloworld.git" ;;
            4) feed_line="src-git openclash https://github.com/vernesong/OpenClash.git;dev" ;;
            5) feed_line="src-git argon https://github.com/jerrykuku/luci-theme-argon.git;master" ;;
            6) feed_line="src-git istore https://github.com/immortalwrt/luci.git;main" ;;
            7) feed_line="src-git homeproxy https://github.com/immortalwrt/homeproxy.git;master" ;;
            8)
                echo -n "  输入 feed 名称: "
                read -r feed_name
                echo -n "  输入 Git 地址: "
                read -r feed_url
                echo -n "  输入分支（留空使用默认）: "
                read -r feed_branch
                if [[ -n "$feed_branch" ]]; then
                    feed_line="src-git ${feed_name} ${feed_url};${feed_branch}"
                else
                    feed_line="src-git ${feed_name} ${feed_url}"
                fi
                ;;
            9)
                # 清除自定义 feeds
                if [[ -f "$custom_feeds_file" ]]; then
                    rm -f "$custom_feeds_file"
                    ok "已清除自定义 feeds"
                fi
                continue
                ;;
            *) continue ;;
        esac

        if [[ -n "$feed_line" ]]; then
            # 添加到 feeds.conf（自定义文件优先）
            if ! grep -q "${feed_line%% *}" "$custom_feeds_file" 2>/dev/null; then
                echo "$feed_line" >> "$custom_feeds_file"
                ok "已添加: ${feed_line%% *}"
            else
                warn "已存在: ${feed_line%% *}"
            fi
        fi
    done

    echo ""
    echo -e "  ${YELLOW}添加后请执行菜单 8 更新并安装 feeds${NC}"

    sep
}

#-------------------- 功能 8：更新并安装 feeds --------------------
update_feeds() {
    sep
    echo -e "${BOLD}          更新并安装 feeds${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    info "更新 feeds（下载软件包定义）..."
    echo -e "  ${YELLOW}这可能需要几分钟...${NC}"
    echo ""

    ./scripts/feeds update -a
    ok "feeds 更新完成"

    echo ""
    info "安装 feeds（创建软件包符号链接）..."
    ./scripts/feeds install -a
    ok "feeds 安装完成"

    echo ""
    echo -e "  ${GREEN}${BOLD}● feeds 更新安装完成！${NC}"
    echo -e "  ${YELLOW}下一步：使用菜单 9 配置编译选项${NC}"

    sep
}

#-------------------- 功能 9：菜单配置 --------------------
menu_config() {
    sep
    echo -e "${BOLD}          打开菜单配置（make menuconfig）${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    # 检查 feeds 是否安装
    if [[ ! -d "package/feeds" ]]; then
        warn "feeds 未安装，先执行 feeds 更新..."
        ./scripts/feeds update -a
        ./scripts/feeds install -a
    fi

    info "打开 menuconfig..."
    echo -e "  ${YELLOW}操作说明：${NC}"
    echo -e "  ${CYAN}  ↑↓    ${NC}移动选项"
    echo -e "  ${CYAN}  Enter  ${NC}进入子菜单"
    echo -e "  ${CYAN}  Y     ${NC}编译进固件 <*>"
    echo -e "  ${CYAN}  M     ${NC}编译为独立包 <M>"
    echo -e "  ${CYAN}  N     ${NC}不编译 < >"
    echo -e "  ${CYAN}  /     ${NC}搜索"
    echo -e "  ${CYAN}  Esc×2 ${NC}返回上级"
    echo -e "  ${CYAN}  Q     ${NC}退出保存"
    echo ""

    make menuconfig

    ok "配置已保存到 .config"

    sep
}

#-------------------- 功能 10：加载预设配置 --------------------
load_preset_config() {
    sep
    echo -e "${BOLD}          加载预设配置${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    echo -e "  ${BOLD}选择预设目标平台：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} x86_64 ${GREEN}（软路由/虚拟机/PC，最常用）${NC}"
    echo -e "  ${CYAN} 2)${NC} x86_32 ${YELLOW}（旧 PC/32位软路由）${NC}"
    echo -e "  ${CYAN} 3)${NC} ARMvirt-64 ${YELLOW}（ARM 虚拟机/树莓派 4/5）${NC}"
    echo -e "  ${CYAN} 4)${NC} generic-aarch64 ${YELLOW}（通用 ARM64）${NC}"
    echo -e "  ${CYAN} 5)${NC} IPQ807x ${YELLOW}（高通 IPQ807x 路由器）${NC}"
    echo -e "  ${CYAN} 6)${NC} MT7986 ${YELLOW}（联发科 MT7986 路由器）${NC}"
    echo -e "  ${CYAN} 7)${NC} 从备份恢复配置"
    echo -e "  ${CYAN} 8)${NC} 自定义 .config 文件"
    echo ""
    echo -n "请选择: "
    read -r preset_choice

    case "$preset_choice" in
        1)
            info "加载 x86_64 预设配置..."
            # 设置目标
            sed -i 's/^CONFIG_TARGET=.*//' .config 2>/dev/null || true
            echo "CONFIG_TARGET=x86" > .config
            echo "CONFIG_TARGET_x86=y" >> .config
            echo "CONFIG_TARGET_x86_64=y" >> .config
            make defconfig
            ok "x86_64 配置已加载，请通过菜单 9 微调"
            ;;
        2)
            info "加载 x86_32 预设配置..."
            echo "CONFIG_TARGET=x86" > .config
            echo "CONFIG_TARGET_x86=y" >> .config
            echo "CONFIG_TARGET_x86_generic=y" >> .config
            make defconfig
            ok "x86_32 配置已加载"
            ;;
        3)
            info "加载 ARMvirt-64 预设配置..."
            echo "CONFIG_TARGET=armvirt" > .config
            echo "CONFIG_TARGET_armvirt=y" >> .config
            echo "CONFIG_TARGET_armvirt_64=y" >> .config
            make defconfig
            ok "ARMvirt-64 配置已加载"
            ;;
        4)
            info "加载 generic-aarch64 预设配置..."
            echo "CONFIG_TARGET=armvirt" > .config
            echo "CONFIG_TARGET_armvirt=y" >> .config
            echo "CONFIG_TARGET_armvirt_64=y" >> .config
            make defconfig
            ok "generic-aarch64 配置已加载"
            ;;
        5)
            info "加载 IPQ807x 预设配置..."
            echo "CONFIG_TARGET=qualcommax" > .config
            echo "CONFIG_TARGET_qualcommax=y" >> .config
            echo "CONFIG_TARGET_qualcommax_ipq807x=y" >> .config
            make defconfig
            ok "IPQ807x 配置已加载"
            ;;
        6)
            info "加载 MT7986 预设配置..."
            echo "CONFIG_TARGET=filogic" > .config
            echo "CONFIG_TARGET_filogic=y" >> .config
            make defconfig
            ok "MT7986 配置已加载"
            ;;
        7)
            # 从备份恢复
            if [[ ! -d "$CONFIG_BACKUP_DIR" ]] || [[ -z "$(ls "$CONFIG_BACKUP_DIR"/*.config 2>/dev/null)" ]]; then
                warn "暂无配置备份"
                return
            fi

            echo ""
            echo -e "  ${BOLD}可用备份：${NC}"
            local idx=1
            declare -A backup_map
            for f in $(ls -t "$CONFIG_BACKUP_DIR"/*.config 2>/dev/null); do
                local fname=$(basename "$f")
                echo -e "  ${CYAN}[$idx]${NC} ${fname}"
                backup_map[$idx]="$f"
                idx=$((idx + 1))
            done

            echo -n "  选择备份编号: "
            read -r backup_idx
            local source="${backup_map[$backup_idx]}"
            if [[ -n "$source" ]]; then
                cp "$source" .config
                make defconfig
                ok "配置已从备份恢复"
            fi
            ;;
        8)
            echo -n "  输入 .config 文件路径: "
            read -r config_path
            if [[ -f "$config_path" ]]; then
                cp "$config_path" .config
                make defconfig
                ok "配置已加载"
            else
                error "文件不存在: ${config_path}"
            fi
            ;;
    esac

    echo ""
    echo -e "  ${YELLOW}建议通过菜单 9 检查和微调配置${NC}"

    sep
}

#-------------------- DIY 配置文件路径 --------------------
DIY_CONFIG_DIR="${BUILD_HOME}/.immortalwrt_diy"
DIY_SETTINGS_FILE="${DIY_CONFIG_DIR}/diy_settings.conf"

#-------------------- 功能 21：DIY 固件定制 --------------------
diy_settings() {
    sep
    echo -e "${BOLD}          DIY 固件定制${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在，请先克隆源码"
        return
    fi

    mkdir -p "$DIY_CONFIG_DIR"

    # 加载已有配置
    if [[ -f "$DIY_SETTINGS_FILE" ]]; then
        source "$DIY_SETTINGS_FILE"
        echo -e "  ${GREEN}已加载上次 DIY 配置${NC}"
        echo ""
    fi

    echo -e "  ${BOLD}═════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}  ImmortalWrt 固件 DIY 定制（所有设置项可选）${NC}"
    echo -e "  ${BOLD}═════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "  ${BOLD}当前默认值（留空保持默认）：${NC}"
    echo ""

    # --- 系统语言 ---
    sep_s
    echo -e "  ${BOLD}【1. 系统语言】${NC}"
    echo -e "  ${CYAN}默认：英文（编译默认）${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 中文（简体）  ${GREEN}（推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} 英文（默认）"
    echo -e "  ${CYAN} 3)${NC} 中文（繁体）"
    echo -e "  ${CYAN} 4)${NC} 日文"
    echo ""
    echo -n "  选择系统语言 [1-4]（默认 1）: "
    read -r lang_choice
    case "$lang_choice" in
        2) DIY_LANG="en" ;;
        3) DIY_LANG="zh_tw" ;;
        4) DIY_LANG="ja" ;;
        *) DIY_LANG="zh_cn" ;;
    esac

    # --- 默认 IP 地址 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【2. LAN 口 IP 地址】${NC}"
    echo -e "  ${CYAN}默认：192.168.1.1${NC}"
    echo -n "  LAN IP 地址（默认 192.168.1.1）: "
    read -r DIY_LAN_IP
    DIY_LAN_IP="${DIY_LAN_IP:-192.168.1.1}"

    # --- root 密码 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【3. Root 密码】${NC}"
    echo -e "  ${CYAN}默认：空密码（无密码直接登录）${NC}"
    echo -n "  Root 密码（留空=无密码）: "
    read -r -s DIY_ROOT_PASS
    echo ""

    # --- 主机名 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【4. 设备主机名】${NC}"
    echo -e "  ${CYAN}默认：ImmortalWrt${NC}"
    echo -n "  主机名（默认 ImmortalWrt）: "
    read -r DIY_HOSTNAME
    DIY_HOSTNAME="${DIY_HOSTNAME:-ImmortalWrt}"

    # --- 时区 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【5. 时区设置】${NC}"
    echo -e "  ${CYAN}默认：UTC${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} Asia/Shanghai  ${GREEN}（中国标准时间，推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} Asia/Taipei   ${YELLOW}（台北时间）${NC}"
    echo -e "  ${CYAN} 3)${NC} Asia/Tokyo     ${YELLOW}（东京时间）${NC}"
    echo -e "  ${CYAN} 4)${NC} UTC            ${YELLOW}（协调世界时）${NC}"
    echo -e "  ${CYAN} 5)${NC} 自定义时区"
    echo ""
    echo -n "  选择时区 [1-5]（默认 1）: "
    read -r tz_choice
    case "$tz_choice" in
        2) DIY_TZ="Asia/Taipei" ;;
        3) DIY_TZ="Asia/Tokyo" ;;
        4) DIY_TZ="UTC" ;;
        5)
            echo -n "  输入时区（如 Europe/London）: "
            read -r DIY_TZ
            ;;
        *) DIY_TZ="CST-8" ;;
    esac

    # --- DNS ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【6. 默认 DNS】${NC}"
    echo -e "  ${CYAN}默认：系统自动${NC}"
    echo -n "  主 DNS（默认 223.5.5.5 阿里DNS）: "
    read -r DIY_DNS1
    DIY_DNS1="${DIY_DNS1:-223.5.5.5}"
    echo -n "  备 DNS（默认 119.29.29.29 腾讯DNS）: "
    read -r DIY_DNS2
    DIY_DNS2="${DIY_DNS2:-119.29.29.29}"

    # --- WiFi 设置 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【7. WiFi 无线设置】${NC}"
    echo -e "  ${CYAN}仅对支持无线网卡的设备有效（x86 虚拟机不适用）${NC}"
    echo ""
    echo -n "  是否配置 WiFi？(y/N): "
    read -r diy_wifi
    if [[ "$diy_wifi" =~ ^[Yy]$ ]]; then
        echo -n "  2.4G WiFi 名称（SSID，默认 ImmortalWrt）: "
        read -r DIY_SSID_24G
        DIY_SSID_24G="${DIY_SSID_24G:-ImmortalWrt}"
        echo -n "  5G WiFi 名称（SSID，默认 ImmortalWrt_5G）: "
        read -r DIY_SSID_5G
        DIY_SSID_5G="${DIY_SSID_5G:-ImmortalWrt_5G}"
        echo -n "  WiFi 密码（默认 12345678，留空=无密码开放网络）: "
        read -r DIY_WIFI_PASS
        DIY_WIFI_PASS="${DIY_WIFI_PASS:-12345678}"
        DIY_WIFI_ENABLED="y"
    else
        DIY_SSID_24G=""
        DIY_SSID_5G=""
        DIY_WIFI_PASS=""
        DIY_WIFI_ENABLED="n"
    fi

    # --- LuCI 主题 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【8. LuCI Web 主题】${NC}"
    echo -e "  ${CYAN}默认：系统默认主题${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} Argon  ${GREEN}（暗蓝色现代主题，推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} design   ${YELLOW}（浅色简洁）${NC}"
    echo -e "  ${CYAN} 3)${NC} rose     ${YELLOW}（粉红色）${NC}"
    echo -e "  ${CYAN} 4)${NC} bootstrap ${YELLOW}（默认原始风格）${NC}"
    echo -e "  ${CYAN} 5)${NC} 不更换主题"
    echo ""
    echo -n "  选择主题 [1-5]（默认 1）: "
    read -r theme_choice
    case "$theme_choice" in
        2) DIY_THEME="design" ;;
        3) DIY_THEME="rose" ;;
        4) DIY_THEME="bootstrap" ;;
        5) DIY_THEME="" ;;
        *) DIY_THEME="argon" ;;
    esac

    # --- 额外软件包 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【9. 额外软件包（编译进固件）】${NC}"
    echo -e "  ${CYAN}默认：基础系统包${NC}"
    echo ""
    echo -e "  ${YELLOW}以下为推荐软件包，可多选（空格分隔编号）${NC}"
    echo ""
    echo -e "  ${CYAN}常用工具:${NC}"
    echo -e "   a) luci-i18n-base-zh-cn      ${GREEN}LuCI 中文基础包${NC}"
    echo -e "   b) luci-app-upnp             ${GREEN}UPnP 端口映射${NC}"
    echo -e "   c) luci-app-uhttpd           ${GREEN}uHTTPd Web 服务器${NC}"
    echo -e "   d) luci-app-ttyd             ${GREEN}网页终端${NC}"
    echo -e "   e) luci-app-filemanager      ${GREEN}文件管理器${NC}"
    echo ""
    echo -e "  ${CYAN}网络工具:${NC}"
    echo -e "   f) luci-app-attendedsysupgrade ${GREEN}在线升级${NC}"
    echo -e "   g) luci-app-opkg             ${GREEN}在线软件包管理${NC}"
    echo -e "   h) luci-app-nlbw            ${GREEN}网络负载均衡${NC}"
    echo -e "   i) luci-app-sqm             ${GREEN}QoS 流量控制${NC}"
    echo ""
    echo -e "  ${CYAN}VPN/代理:${NC}"
    echo -e "   j) luci-app-ssr-plus         ${GREEN}SSR Plus+（需先加 feeds）${NC}"
    echo -e "   k) luci-app-passwall         ${GREEN}PassWall（需先加 feeds）${NC}"
    echo -e "   l) luci-app-openclash        ${GREEN}OpenClash（需先加 feeds）${NC}"
    echo -e "   m) luci-app-wireguard        ${GREEN}WireGuard VPN${NC}"
    echo ""
    echo -e "  ${CYAN}磁盘:${NC}"
    echo -e "   n) luci-app-diskman           ${GREEN}磁盘管理${NC}"
    echo -e "   o) luci-app-docker            ${GREEN}Docker 管理${NC}"
    echo -e "   p) luci-app-ttyd             ${GREEN}网页终端${NC}"
    echo ""
    echo -e "  ${CYAN}全部推荐${NC}"
    echo -e "   x) 全部安装（a+b+c+d+e+f+g+m+n）${NC}"
    echo -e "   q) 跳过，不添加额外软件包"
    echo ""
    echo -n "  选择（可多选，空格分隔）: "
    read -r pkg_choices

    DIY_EXTRA_PKGS=""
    DIY_EXTRA_PKG_LIST=""

    case "$pkg_choices" in
        x)
            DIY_EXTRA_PKGS="luci-i18n-base-zh-cn luci-app-upnp luci-app-uhttpd luci-app-ttyd luci-app-filemanager luci-app-attendedsysupgrade luci-app-opkg luci-app-wireguard luci-app-diskman"
            DIY_EXTRA_PKG_LIST="LuCI中文基础包、UPnP、uHTTPd、网页终端、文件管理器、在线升级、软件包管理、WireGuard、磁盘管理"
            ;;
        q|"")
            DIY_EXTRA_PKGS=""
            DIY_EXTRA_PKG_LIST="无"
            ;;
        *)
            local pkg_map="a:luci-i18n-base-zh-cn b:luci-app-upnp c:luci-app-uhttpd d:luci-app-ttyd e:luci-app-filemanager f:luci-app-attendedsysupgrade g:luci-app-opkg h:luci-app-nlbw i:luci-app-sqm j:luci-app-ssr-plus k:luci-app-passwall l:luci-app-openclash m:luci-app-wireguard n:luci-app-diskman o:luci-app-docker p:luci-app-ttyd"
            for c in $pkg_choices; do
                for entry in $pkg_map; do
                    local key="${entry%%:*}"
                    local val="${entry##*:}"
                    if [[ "$c" == "$key" ]]; then
                        DIY_EXTRA_PKGS="${DIY_EXTRA_PKGS} ${val}"
                        DIY_EXTRA_PKG_LIST="${DIY_EXTRA_PKG_LIST}, ${val}"
                        break
                    fi
                done
            done
            DIY_EXTRA_PKG_LIST=${DIY_EXTRA_PKG_LIST#, }
            ;;
    esac

    # --- 开机自动脚本 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【10. 开机自定义脚本】${NC}"
    echo -e "  ${CYAN}固件首次启动时自动执行的命令（uci-defaults）${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 启用 IPv6"
    echo -e "  ${CYAN} 2)${NC} 禁用 IPv6"
    echo -e "  ${CYAN} 3)${NC} 开启组播支持"
    echo -e "  ${CYAN} 4)${NC} 自定义命令"
    echo ""
    echo -n "  选择额外开机配置（多选用空格分隔，留空跳过）: "
    read -r boot_choices
    DIY_BOOT_EXTRAS="$boot_choices"

    echo -n "  自定义 uci 命令（如 firewall.default_accept=1，留空跳过）: "
    read -r DIY_CUSTOM_UCI

    # --- LED/UART ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【11. 硬件相关】${NC}"
    echo -e "  ${CYAN}仅适用于特定硬件平台（如路由器）${NC}"
    echo ""
    echo -n "  是否自定义硬件配置？（一般跳过，y/N）: "
    read -r diy_hw
    DIY_HW_ENABLED="${diy_hw:-n}"

    # --- 保存配置 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}保存 DIY 配置...${NC}"

    cat > "$DIY_SETTINGS_FILE" <<EOF
# ImmortalWrt DIY 定制配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 语言
DIY_LANG="${DIY_LANG}"
# IP
DIY_LAN_IP="${DIY_LAN_IP}"
# Root 密码
DIY_ROOT_PASS="${DIY_ROOT_PASS}"
# 主机名
DIY_HOSTNAME="${DIY_HOSTNAME}"
# 时区
DIY_TZ="${DIY_TZ}"
# DNS
DIY_DNS1="${DIY_DNS1}"
DIY_DNS2="${DIY_DNS2}"
# WiFi
DIY_WIFI_ENABLED="${DIY_WIFI_ENABLED}"
DIY_SSID_24G="${DIY_SSID_24G}"
DIY_SSID_5G="${DIY_SSID_5G}"
DIY_WIFI_PASS="${DIY_WIFI_PASS}"
# 主题
DIY_THEME="${DIY_THEME}"
# 额外软件包
DIY_EXTRA_PKGS="${DIY_EXTRA_PKGS}"
DIY_EXTRA_PKG_LIST="${DIY_EXTRA_PKG_LIST}"
# 开机配置
DIY_BOOT_EXTRAS="${DIY_BOOT_EXTRAS}"
DIY_CUSTOM_UCI="${DIY_CUSTOM_UCI}"
# 硬件
DIY_HW_ENABLED="${DIY_HW_ENABLED}"
EOF

    chmod 600 "$DIY_SETTINGS_FILE"

    ok "DIY 配置已保存到 ${DIY_SETTINGS_FILE}"
    echo ""
    diy_show_summary

    sep
}

#-------------------- DIY 配置摘要 --------------------
diy_show_summary() {
    if [[ ! -f "$DIY_SETTINGS_FILE" ]]; then
        warn "无 DIY 配置"
        return
    fi

    source "$DIY_SETTINGS_FILE"

    sep_s
    echo -e "  ${BOLD}当前 DIY 配置摘要：${NC}"
    sep_s
    echo ""
    echo -e "  ${BLUE}系统语言：${NC}$([[ "$DIY_LANG" == "zh_cn" ]] && echo "中文简体" || ([[ "$DIY_LANG" == "zh_tw" ]] && echo "中文繁體" || ([[ "$DIY_LANG" == "ja" ]] && echo "日本語" || echo "English")))"
    echo -e "  ${BLUE}LAN IP  ：${NC}${DIY_LAN_IP}"
    echo -e "  ${BLUE}Root密码：${NC}${DIY_ROOT_PASS:-无密码（空）}"
    echo -e "  ${BLUE}用户名  ：${NC}${DIY_USERNAME:-root}"
    echo -e "  ${BLUE}主机名  ：${NC}${DIY_HOSTNAME}"
    echo -e "  ${BLUE}时区    ：${NC}${DIY_TZ}"
    echo -e "  ${BLUE}DNS     ：${NC}${DIY_DNS1:-自动} / ${DIY_DNS2:-自动}"

    if [[ "$DIY_WIFI_ENABLED" == "y" ]]; then
        echo -e "  ${BLUE}WiFi 2.4G：${NC}${DIY_SSID_24G} / ${DIY_WIFI_PASS}"
        echo -e "  ${BLUE}WiFi 5G  ：${NC}${DIY_SSID_5G} / ${DIY_WIFI_PASS}"
    else
        echo -e "  ${BLUE}WiFi    ：${NC}未配置"
    fi

    echo -e "  ${BLUE}主题    ：${NC}${DIY_THEME:-默认}"
    echo -e "  ${BLUE}分区    ：${NC}${DIY_TARGET_ROOTFS:-squashfs}"
    echo -e "  ${BLUE}SSH     ：${NC}$([[ "${DIY_SSH_DROPBEAR:-y}" == "n" ]] && echo "OpenSSH" || echo "Dropbear") 端口${DIY_SSH_PORT:-22}$([[ "${DIY_SSH_KEY_ONLY:-n}" == "y" ]] && echo " (仅密钥)" || echo "")"
    echo -e "  ${BLUE}LuCI    ：${NC}$([[ "${DIY_LUCI_HTTPS:-http}" == "https_only" ]] && echo "仅HTTPS" || ([[ "${DIY_LUCI_HTTPS:-}" == "both" ]] && echo "HTTP+HTTPS" || echo "HTTP"))"
    echo -e "  ${BLUE}WAN     ：${NC}${DIY_WAN_PROTO:-默认DHCP}"
    echo -e "  ${BLUE}防火墙  ：${NC}$([[ "${DIY_FW_MODE:-default}" == "open" ]] && echo "全开放" || ([[ "${DIY_FW_MODE:-}" == "ip_whitelist" ]] && echo "IP白名单(${DIY_LUCI_IP})" || ([[ "${DIY_FW_MODE:-}" == "custom" ]] && echo "自定义端口(${DIY_FW_PORTS})" || echo "默认")))"

    if [[ -n "$DIY_EXTRA_PKG_LIST" ]]; then
        echo -e "  ${BLUE}额外软件：${NC}${DIY_EXTRA_PKG_LIST}"
    else
        echo -e "  ${BLUE}额外软件：${NC}无"
    fi

    if [[ -n "${DIY_KERNEL_MODULES:-}" ]] && [[ "$DIY_KERNEL_MODULES" != "none" ]]; then
        echo -e "  ${BLUE}内核模块：${NC}${DIY_KERNEL_MODULES}"
    fi

    echo ""
}

#-------------------- 功能 22：DIY 一键应用到源码 --------------------
diy_preset_apply() {
    sep
    echo -e "${BOLD}          DIY 配置应用到源码${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    if [[ ! -f "$DIY_SETTINGS_FILE" ]]; then
        warn "无 DIY 配置，请先使用菜单 21 配置"
        return
    fi

    source "$DIY_SETTINGS_FILE"
    cd "$SOURCE_DIR"

    echo ""
    echo -e "  ${BOLD}确认以下 DIY 配置将应用到源码：${NC}"
    diy_show_summary
    echo ""
    echo -n "  确认应用？(Y/n): "
    read -r confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return

    echo ""
    info "开始应用 DIY 配置..."

    local files_dir="package/base-files/files"
    mkdir -p "${files_dir}/etc/uci-defaults"

    # ===== 1. 创建 uci-defaults 初始化脚本 =====
    local uci_script="${files_dir}/etc/uci-defaults/99-default-settings"

    cat > "$uci_script" <<'UCIHEADER'
#!/bin/sh
# ImmortalWrt DIY 定制初始化脚本
# 此脚本仅在首次启动时执行一次，执行后会自动删除

UCIHEADER

    cat >> "$uci_script" <<UCIBODY
# 执行标志，防止重复执行
exit_if_settings_applied() {
    local mark="${mark:-immortalwrt_diy_done}"
    if [ -f "/etc/config/${mark}" ]; then
        echo "DIY settings already applied, skipping..."
        return 0
    else
        touch "/etc/config/${mark}"
    fi
    return 1
}

# ===== 系统语言 =====
UCIBODY

    # 设置 LuCI 中文
    if [[ "$DIY_LANG" == "zh_cn" ]]; then
        cat >> "$uci_script" <<EOF
uci set luci.main.lang=zh_cn
EOF
    elif [[ "$DIY_LANG" == "zh_tw" ]]; then
        cat >> "$uci_script" <<EOF
uci set luci.main.lang=zh_tw
EOF
    elif [[ "$DIY_LANG" == "ja" ]]; then
        cat >> "$uci_script" <<EOF
uci set luci.main.lang=ja
EOF
    fi

    cat >> "$uci_script" <<'UCIBODY2'

# ===== Root 密码 =====
UCIBODY2

    if [[ -n "$DIY_ROOT_PASS" ]]; then
        cat >> "$uci_script" <<EOF
echo -e "${DIY_ROOT_PASS}\n${DIY_ROOT_PASS}" | passwd root
EOF
    else
        cat >> "$uci_script" <<'EOF'
# 空密码（默认）
passwd -l root 2>/dev/null || true
EOF
    fi

    cat >> "$uci_script" <<'UCIBODY3'

# ===== 主机名 =====
UCIBODY3

    cat >> "$uci_script" <<EOF
uci set system.@system[0].hostname='${DIY_HOSTNAME}'
uci set system.@system[0].timezone='${DIY_TZ}'
EOF

    # --- 修改 LAN IP ---
    local old_ip=$(uci -q get network.lan.ipaddr)
    local new_ip="${DIY_LAN_IP}"

    if [[ "$new_ip" != "192.168.1.1" ]]; then
        cat >> "$uci_script" <<EOF

# 修改 LAN IP 地址
uci set network.lan.ipaddr='${new_ip}'
uci set network.lan.gateway='${new_ip%.*}.1'
uci set network.lan.dns='${DIY_DNS1} ${DIY_DNS2}'
uci delete network.lan.dns
uci add_list network.lan.dns '${DIY_DNS1}'
uci add_list network.lan.dns '${DIY_DNS2}'

# 更新 WAN 口的网关（防止与 LAN 冲突）
uci set network.wan.metric='10'
uci set network.lan.metric='0'
EOF
    else
        cat >> "$uci_script" <<EOF

# 仅修改 DNS
uci delete network.lan.dns
uci add_list network.lan.dns '${DIY_DNS1}'
uci add_list network.lan.dns '${DIY_DNS2}'
EOF
    fi

    cat >> "$uci_script" <<'UCIBODY4'

# ===== WiFi 设置 =====
UCIBODY4

    if [[ "$DIY_WIFI_ENABLED" == "y" ]]; then
        cat >> "$uci_script" <<EOF

# WiFi 2.4G 设置
uci set wireless.@wifi-iface[0].ssid='${DIY_SSID_24G}'
uci set wireless.@wifi-iface[0].encryption='psk2+ccmp'
uci set wireless.@wifi-iface[0].key='${DIY_WIFI_PASS}'
uci set wireless.@wifi-iface[0].disabled='0'

# WiFi 5G 设置
uci set wireless.@wifi-iface[1].ssid='${DIY_SSID_5G}'
uci set wireless.@wifi-iface[1].encryption='psk2+ccmp'
uci set wireless.@wifi-iface[1].key='${DIY_WIFI_PASS}'
uci set wireless.@wifi-iface[1].disabled='0'
EOF

        # 如果用户没有自定义 SSID，则根据语言设置默认名称
        if [[ "$DIY_LANG" == "zh_cn" && "$DIY_SSID_24G" == "ImmortalWrt" && "$DIY_SSID_5G" == "ImmortalWrt_5G" ]]; then
            cat >> "$uci_script" <<'EOF'
uci set wireless.@wifi-iface[0].ssid='ImmortalWrt'
uci set wireless.@wifi-iface[1].ssid='ImmortalWrt_5G'
EOF
        fi
    fi

    cat >> "$uci_script" <<'UCIBODY5'

# ===== 开机额外配置 =====
UCIBODY5

    if [[ "${DIY_BOOT_EXTRAS:-}" == *"1"* ]]; then
        cat >> "$uci_script" <<'EOF'
# 启用 IPv6
uci set network.globals.ip6class='wan6'
uci set network.wan.ipv6='1'
EOF
    fi

    if [[ "${DIY_BOOT_EXTRAS:-}" == *"2"* ]]; then
        cat >> "$uci_script" <<'EOF'
# 禁用 IPv6
uci set network.wan.ipv6='0'
uci delete network.lan.ip6addr
EOF
    fi

    if [[ "${DIY_BOOT_EXTRAS:-}" == *"3"* ]]; then
        cat >> "$uci_script" <<'EOF'
# 组播支持
uci set network.globals.multicast_router='1'
EOF
    fi

    # 自定义 uci 命令
UCIBODY5

    if [[ -n "${DIY_CUSTOM_UCI:-}" ]]; then
        for uci_cmd in $DIY_CUSTOM_UCI; do
            local uci_key=$(echo "$uci_cmd" | cut -d= -f1)
            local uci_val=$(echo "$uci_cmd" | cut -d= -f2-)
            if [[ -n "$uci_key" ]] && [[ -n "$uci_val" ]]; then
                cat >> "$uci_script" <<EOF
uci set ${uci_key}='${uci_val}'
EOF
            fi
        done
    fi

    # ===== 高级设置部分 =====

    # --- 用户名 ---
    if [[ -n "${DIY_USERNAME:-}" ]] && [[ "$DIY_USERNAME" != "root" ]]; then
        cat >> "$uci_script" <<EOF

# 创建自定义管理员用户
user add '${DIY_USERNAME}' -G root
echo -e "${DIY_ROOT_PASS}\n${DIY_ROOT_PASS}" | passwd '${DIY_USERNAME}'
EOF
    fi

    # --- WAN 口设置 ---
    if [[ -n "${DIY_WAN_PROTO:-}" ]]; then
        cat >> "$uci_script" <<EOF

# WAN 口设置
uci set network.wan.proto='${DIY_WAN_PROTO}'
EOF
        if [[ "$DIY_WAN_PROTO" == "pppoe" && -n "${DIY_PPPOE_USER:-}" ]]; then
            cat >> "$uci_script" <<EOF
uci set network.wan.username='${DIY_PPPOE_USER}'
uci set network.wan.password='${DIY_PPPOE_PASS}'
EOF
        elif [[ "$DIY_WAN_PROTO" == "static" ]]; then
            cat >> "$uci_script" <<EOF
uci set network.wan.ipaddr='${DIY_WAN_IP:-}'
uci set network.wan.netmask='${DIY_WAN_MASK:-255.255.255.0}'
uci set network.wan.gateway='${DIY_WAN_GW:-}'
EOF
        fi
    fi

    # --- 防火墙 ---
    if [[ "${DIY_FW_MODE:-default}" == "open" ]]; then
        cat >> "$uci_script" <<'EOF'

# 开放所有端口（仅测试用）
uci set firewall.default.input='ACCEPT'
uci set firewall.default.forward='ACCEPT'
uci set firewall.default.output='ACCEPT'
EOF
    elif [[ "${DIY_FW_MODE:-}" == "custom" && -n "${DIY_FW_PORTS:-}" ]]; then
        cat >> "$uci_script" <<'EOF'

# 自定义防火墙规则
EOF
        for port in $DIY_FW_PORTS; do
            cat >> "$uci_script" <<EOF
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-${port}'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='${port}'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].target='ACCEPT'
EOF
        done
    elif [[ "${DIY_FW_MODE:-}" == "ip_whitelist" && -n "${DIY_LUCI_IP:-}" ]]; then
        cat >> "$uci_script" <<EOF

# 限制 LuCI 仅允许指定 IP 访问
uci set firewall.@defaults[0].input='DROP'
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-LuCI-${DIY_LUCI_IP}'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].src_ip='${DIY_LUCI_IP}'
uci set firewall.@rule[-1].dest_port='80 443'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-LAN-Access'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].target='ACCEPT'
EOF
    fi

    # --- LED ---
    if [[ "${DIY_LED:-default}" == "off" ]]; then
        cat >> "$uci_script" <<'EOF'

# 关闭所有 LED
uci set system.@system[0].led_off='1'
for led in /sys/class/leds/*; do
    echo none > "\$led/trigger" 2>/dev/null || true
    echo 0 > "\$led/brightness" 2>/dev/null || true
done
EOF
    elif [[ "${DIY_LED:-}" == "heartbeat" ]]; then
        cat >> "$uci_script" <<'EOF'

# LED 心跳闪烁
for led in /sys/class/leds/*; do
    echo heartbeat > "\$led/trigger" 2>/dev/null || true
done
EOF
    fi

    # --- SSH ---
    if [[ "${DIY_SSH_DROPBEAR:-y}" == "n" ]]; then
        cat >> "$uci_script" <<'EOF'

# 替换 Dropbear 为 OpenSSH
opkg remove dropbear 2>/dev/null || true
EOF
    fi
    if [[ -n "${DIY_SSH_PORT:-}" ]] && [[ "${DIY_SSH_PORT}" != "22" ]]; then
        cat >> "$uci_script" <<EOF

# 修改 SSH 端口
uci set sshd.@sshd[0].Port='${DIY_SSH_PORT}' 2>/dev/null || \
uci set dropbear.@dropbear[0].Port='${DIY_SSH_PORT}' 2>/dev/null || true
uci set firewall.@rule[0].dest_port='${DIY_SSH_PORT}'
EOF
    fi
    if [[ "${DIY_SSH_KEY_ONLY:-n}" == "y" ]]; then
        cat >> "$uci_script" <<'EOF'

# SSH 仅允许密钥登录
uci set dropbear.@dropbear[0].PasswordAuth='0' 2>/dev/null || true
uci set sshd.@sshd[0].PasswordAuthentication='no' 2>/dev/null || true
EOF
    fi

    # --- LuCI HTTPS ---
    if [[ "${DIY_LUCI_HTTPS:-http}" == "https_only" ]]; then
        cat >> "$uci_script" <<'EOF'

# 配置 LuCI HTTPS
uci set uhttpd.main.listen_http='0.0.0.0:80'
uci set uhttpd.main.redirect_https='1'
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci set uhttpd.main.cert='/etc/uhttpd.crt'
uci set uhttpd.main.key='/etc/uhttpd.key'
EOF
    elif [[ "${DIY_LUCI_HTTPS:-}" == "both" ]]; then
        cat >> "$uci_script" <<'EOF'

# 同时启用 HTTP 和 HTTPS
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci set uhttpd.main.cert='/etc/uhttpd.crt'
uci set uhttpd.main.key='/etc/uhttpd.key'
EOF
    fi

    # --- 服务优化 ---
    if [[ "${DIY_SVC_CONFIG:-}" == *"1"* ]]; then
        cat >> "$uci_script" <<'EOF'

# 禁用 logd 写入磁盘，改为 RAM
uci set system.@system[0].log_size='64'
uci set system.@system[0].log_proto='udp'
EOF
    fi
    if [[ "${DIY_SVC_CONFIG:-}" == *"2"* ]]; then
        cat >> "$uci_script" <<'EOF'

# logd 写入 RAM
mkdir -p /tmp/log
uci set system.@system[0].log_file='/tmp/log/system.log'
EOF
    fi
    if [[ "${DIY_SVC_CONFIG:-}" == *"4"* ]]; then
        cat >> "$uci_script" <<'EOF'

# 禁用 WAN DNS 侦听
uci set dhcp.@dnsmasq[0].nonwildcard='1'
uci set dhcp.@dnsmasq[0].local_service='1'
EOF
    fi

    # --- rc.local 注入 ---
    if [[ -n "${DIY_RC_LOCAL:-}" ]]; then
        cat >> "$uci_script" <<'RCLOCAL_MARKER'

# ===== 自定义 rc.local =====
RCLOCAL_MARKER
        # 将 DIY_RC_LOCAL 内容写入
        cat >> "$uci_script" <<EOF
cat >> /etc/rc.local <<'RCLocalEOF'
${DIY_RC_LOCAL}RCLocalEOF
EOF
    fi

    # --- 自定义 config 文件 ---
    if [[ -n "${DIY_CUSTOM_CFG_NAME:-}" ]]; then
        cat >> "$uci_script" <<'CFG_MARKER'

# ===== 自定义配置文件 =====
CFG_MARKER
        cat >> "$uci_script" <<EOFCFG
cat > /etc/config/${DIY_CUSTOM_CFG_NAME} <<'CustomCfgEOF'
${DIY_CUSTOM_CFG_CONTENT}CustomCfgEOF
EOFCFG
    fi

    cat >> "$uci_script" <<'UCIBODY6'

# ===== 完成设置 =====
UCIBODY6

    cat >> "$uci_script" <<'EOF'
uci commit

# 设置完成标记
echo "immortalwrt_diy_done" > /etc/config/immortalwrt_diy_done

exit 0
EOF

    chmod +x "$uci_script"
    ok "初始化脚本已创建: ${uci_script}"

    # ===== 2. 修改 .config 添加中文语言包 =====
    echo ""
    info "添加中文语言包到 .config..."
    local lang_pkg=""
    if [[ "$DIY_LANG" == "zh_cn" ]]; then
        lang_pkg="luci-i18n-base-zh-cn"
    elif [[ "$DIY_LANG" == "zh_tw" ]]; then
        lang_pkg="luci-i18n-base-zh-tw"
    elif [[ "$DIY_LANG" == "ja" ]]; then
        lang_pkg="luci-i18n-base-ja"
    fi

    if [[ -n "$lang_pkg" ]]; then
        # 确保 .config 中启用语言包
        if [[ -f .config ]]; then
            if ! grep -q "CONFIG_PACKAGE_${lang_pkg}=y" .config 2>/dev/null; then
                # 先更新 feeds 获取语言包
                info "确保 feeds 中有语言包..."
                ./scripts/feeds install "$lang_pkg" 2>/dev/null || true
                echo "CONFIG_PACKAGE_${lang_pkg}=y" >> .config
                # 如果已有其他语言包，也启用
                echo "CONFIG_PACKAGE_luci-i18n-opkg-zh-cn=m" >> .config 2>/dev/null
                echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=m" >> .config 2>/dev/null
                ok "语言包 ${lang_pkg} 已添加"
            else
                ok "语言包 ${lang_pkg} 已在配置中"
            fi
        fi
    fi

    # ===== 3. 修改 .config 添加额外软件包 =====
    if [[ -n "$DIY_EXTRA_PKGS" ]]; then
        echo ""
        info "添加额外软件包..."
        for pkg in $DIY_EXTRA_PKGS; do
            if [[ -f .config ]]; then
                if ! grep -q "CONFIG_PACKAGE_${pkg}" .config 2>/dev/null; then
                    ./scripts/feeds install "$pkg" 2>/dev/null || true
                    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
                    ok "已添加: ${pkg}"
                else
                    ok "已存在: ${pkg}"
                fi
            fi
        done
    fi

    # ===== 4. 修改 .config 添加 LuCI 主题 =====
    if [[ -n "$DIY_THEME" ]]; then
        echo ""
        info "添加 LuCI 主题..."
        local theme_pkg="luci-theme-${DIY_THEME}"
        if [[ -f .config ]]; then
            ./scripts/feeds install "$theme_pkg" 2>/dev/null || true
            echo "CONFIG_PACKAGE_${theme_pkg}=y" >> .config
            # 设置默认主题
            echo "CONFIG_LUCI_THEME_${DIY_THEME^^}=y" >> .config
            ok "主题 ${DIY_THEME} 已添加"
        fi
    fi

    # ===== 5. 修改 .config 添加内核/驱动模块 =====
    if [[ -n "${DIY_KERNEL_MODULES:-}" ]] && [[ "$DIY_KERNEL_MODULES" != "none" ]]; then
        echo ""
        info "添加内核/驱动模块..."
        for mod in $DIY_KERNEL_MODULES; do
            if [[ "$mod" == CONFIG_* ]]; then
                echo "${mod}" >> .config
                ok "已添加内核配置: ${mod}"
            else
                if [[ -f .config ]]; then
                    ./scripts/feeds install "$mod" 2>/dev/null || true
                    echo "CONFIG_PACKAGE_${mod}=y" >> .config
                    ok "已添加模块: ${mod}"
                fi
            fi
        done
    fi

    # ===== 6. SSH 配置 =====
    if [[ "${DIY_SSH_DROPBEAR:-y}" == "n" ]]; then
        echo ""
        info "配置 OpenSSH（移除 Dropbear）..."
        if [[ -f .config ]]; then
            sed -i 's/CONFIG_PACKAGE_dropbear=y/CONFIG_PACKAGE_dropbear=n/' .config 2>/dev/null || true
            echo "CONFIG_PACKAGE_openssh-server=y" >> .config
            echo "CONFIG_PACKAGE_openssh-keygen=y" >> .config
            ok "已配置 OpenSSH"
        fi
    fi

    # ===== 7. 分区方案 =====
    if [[ -n "${DIY_TARGET_ROOTFS:-}" ]]; then
        case "$DIY_TARGET_ROOTFS" in
            ext4)
                echo ""
                info "配置 ext4 根文件系统..."
                if [[ -f .config ]]; then
                    echo "CONFIG_TARGET_ROOTFS_PARTNAME=/dev/sda2" >> .config 2>/dev/null || true
                    ok "已配置 ext4"
                fi
                ;;
            squashfs+ext4)
                echo ""
                info "配置 squashfs + ext4 overlay..."
                ;;
        esac
    fi

    # ===== 8. 版本差异自动适配 =====
    echo ""
    info "版本差异自动适配..."
    # 检测源码版本自动调整配置
    local iw_ver="unknown"
    iw_ver=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
    if [[ "$iw_ver" != *"24."* ]] && [[ "$iw_ver" != *"25."* ]] && [[ "$iw_ver" != *"master"* ]]; then
        # 旧版本可能没有某些包，静默忽略
        warn "检测到较旧版本 ${iw_ver}，部分包可能不存在"
        info "如遇到编译错误，请使用 menuconfig 检查"
    fi
    # 检查主题是否存在
    if [[ -n "$DIY_THEME" ]]; then
        if [[ ! -d "feeds/luci/themes/luci-theme-${DIY_THEME}" ]] && [[ ! -d "package/feeds/luci/luci-theme-${DIY_THEME}" ]]; then
            warn "主题 ${DIY_THEME} 不存在于当前 feeds 中"
            warn "请先通过菜单 7 添加包含该主题的 feeds 源"
        fi
    fi
    ok "版本适配完成"

    # ===== 9. defconfig 整合 =====
    echo ""
    info "运行 defconfig 整合所有配置..."
    make defconfig 2>/dev/null

    echo ""
    echo -e "  ${GREEN}${BOLD}● DIY 配置已应用到源码！${NC}"
    echo -e "  ${YELLOW}下一步：${NC}"
    echo -e "  ${CYAN}  1. 可通过菜单 9 (menuconfig) 检查和微调${NC}"
    echo -e "  ${CYAN}  2. 然后使用菜单 13 编译固件${NC}"

    sep
}

#-------------------- 功能 23：查看/导出 DIY 配置 --------------------
diy_show_export() {
    sep
    echo -e "${BOLD}          查看/导出/导入 DIY 配置${NC}"
    sep
    echo ""

    if [[ ! -f "$DIY_SETTINGS_FILE" ]]; then
        warn "无 DIY 配置，请先使用菜单 21 或 23 配置"
        echo ""
        echo -e "  ${CYAN} 1)${NC} 从文件导入 DIY 配置"
        echo -e "  ${CYAN} 0)${NC} 返回"
        echo ""
        echo -n "请选择: "
        read -r no_config_choice
        case "$no_config_choice" in
            1) diy_import_config ;;
        esac
        return
    fi

    diy_show_summary

    echo ""
    echo -e "  ${BOLD}操作选项：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 导出为 shell 脚本（可手动修改后重新导入）"
    echo -e "  ${CYAN} 2)${NC} 导出 uci-defaults 脚本到本地"
    echo -e "  ${CYAN} 3)${NC} 从文件导入 DIY 配置"
    echo -e "  ${CYAN} 4)${NC} 清除 DIY 配置"
    echo ""
    echo -n "请选择: "
    read -r export_choice

    case "$export_choice" in
        1)
            local export_file="${DIY_CONFIG_DIR}/diy_export_$(date +%Y%m%d_%H%M%S).sh"
            cp "$DIY_SETTINGS_FILE" "$export_file"
            chmod 600 "$export_file"
            ok "已导出到: ${export_file}"
            echo -e "  ${YELLOW}可编辑此文件后通过导入功能重新加载${NC}"
            ;;
        2)
            if [[ -d "$SOURCE_DIR/package/base-files/files/etc/uci-defaults" ]]; then
                local uci_file="${SOURCE_DIR}/package/base-files/files/etc/uci-defaults/99-default-settings"
                if [[ -f "$uci_file" ]]; then
                    local local_export="${BUILD_HOME}/uci-defaults-99-default-settings_$(date +%Y%m%d_%H%M%S)"
                    cp "$uci_file" "$local_export"
                    ok "已导出到: ${local_export}"
                else
                    warn "未找到 uci-defaults 脚本，请先使用菜单 24 应用 DIY"
                fi
            else
                warn "请先使用菜单 24 应用 DIY 配置"
            fi
            ;;
        3)
            diy_import_config
            ;;
        4)
            rm -f "$DIY_SETTINGS_FILE"
            ok "DIY 配置已清除"
            ;;
    esac

    sep
}

#-------------------- 导入 DIY 配置 --------------------
diy_import_config() {
    echo ""
    echo -e "  ${BOLD}导入 DIY 配置${NC}"
    echo ""

    # 列出可导入的文件
    local found=false
    if [[ -d "$DIY_CONFIG_DIR" ]]; then
        echo -e "  ${BOLD}可导入的配置文件：${NC}"
        echo ""
        local idx=1
        declare -A import_map
        shopt -s nullglob
        for f in "$DIY_CONFIG_DIR"/diy_export_*.sh "$DIY_CONFIG_DIR"/diy_settings.conf; do
            [[ -f "$f" ]] || continue
            local fname=$(basename "$f")
            echo -e "  ${CYAN}[${idx}]${NC} ${fname}"
            import_map[$idx]="$f"
            found=true
            idx=$((idx + 1))
        done
    fi

    if [[ "$found" == false ]]; then
        echo -e "  ${YELLOW}无已导出的配置文件${NC}"
        echo ""
        echo -n "  输入配置文件完整路径（或 Enter 取消）: "
        read -r import_path
        if [[ -z "$import_path" || ! -f "$import_path" ]]; then
            warn "已取消"
            return
        fi
    else
        echo ""
        echo -e "  ${CYAN} [o]${NC} 手动输入文件路径"
        echo -n "  选择编号或输入路径（Enter 取消）: "
        read -r import_sel
        if [[ -z "$import_sel" ]]; then
            info "已取消"
            return
        fi
        if [[ "$import_sel" == "o" || "$import_sel" == "O" ]]; then
            echo -n "  输入文件路径: "
            read -r import_path
        else
            import_path="${import_map[$import_sel]:-}"
        fi
    fi

    if [[ -z "$import_path" || ! -f "$import_path" ]]; then
        error "文件不存在"
        return
    fi

    # 验证文件格式
    if ! grep -q "DIY_LANG=" "$import_path" 2>/dev/null; then
        error "文件格式不正确（缺少 DIY_LANG）"
        return
    fi

    # 导入
    mkdir -p "$DIY_CONFIG_DIR"
    cp "$import_path" "$DIY_SETTINGS_FILE"
    chmod 600 "$DIY_SETTINGS_FILE"

    ok "DIY 配置已从 ${import_path} 导入"
    echo ""
    diy_show_summary

    sep
}

#-------------------- 功能 22：DIY 高级设置 --------------------
diy_advanced_settings() {
    sep
    echo -e "${BOLD}          DIY 高级设置${NC}"
    sep
    echo ""

    mkdir -p "$DIY_CONFIG_DIR"

    # 加载已有配置
    if [[ -f "$DIY_SETTINGS_FILE" ]]; then
        source "$DIY_SETTINGS_FILE"
        echo -e "  ${GREEN}已加载上次 DIY 配置${NC}"
        echo ""
    else
        warn "建议先使用菜单 21 完成基础设置"
        echo ""
    fi

    # --- 检测当前版本 ---
    local iw_version="unknown"
    if [[ -d "$SOURCE_DIR" ]]; then
        iw_version=$(cd "$SOURCE_DIR" 2>/dev/null && git describe --tags --abbrev=0 2>/dev/null || git branch --show-current 2>/dev/null || echo "unknown")
    fi
    echo -e "  ${BLUE}当前版本：${NC}${iw_version}"
    echo ""

    sep_s
    echo -e "  ${BOLD}═════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}  ImmortalWrt 高级 DIY 定制${NC}"
    echo -e "  ${BOLD}═════════════════════════════════════════════════${NC}"
    echo ""

    # --- 默认登录用户名 ---
    echo -e "  ${BOLD}【1. 默认登录用户名】${NC}"
    echo -e "  ${CYAN}OpenWrt 默认为 root，ImmortalWrt 默认为 root${NC}"
    echo -e "  ${YELLOW}注意：修改用户名需额外包 luci-mod-rpc，且可能影响部分功能${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 保持 root（默认）"
    echo -e "  ${CYAN} 2)${NC} 自定义用户名"
    echo ""
    echo -n "  选择 [1-2]（默认 1）: "
    read -r user_choice
    case "$user_choice" in
        2)
            echo -n "  自定义用户名（如 admin）: "
            read -r DIY_USERNAME
            DIY_USERNAME="${DIY_USERNAME:-root}"
            if [[ "$DIY_USERNAME" != "root" ]]; then
                # 同时要创建这个用户并设置密码
                echo -e "  ${YELLOW}将创建用户 ${DIY_USERNAME} 并设置管理员权限${NC}"
            fi
            ;;
        *) DIY_USERNAME="root" ;;
    esac

    # --- WAN 口设置 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【2. WAN 口默认设置】${NC}"
    echo -e "  ${CYAN}适用于作为主路由使用的场景${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} DHCP 自动获取（默认）"
    echo -e "  ${CYAN} 2)${NC} PPPoE 拨号"
    echo -e "  ${CYAN} 3)${NC} 静态 IP"
    echo -e "  ${CYAN} 4)${NC} 跳过（保持默认）"
    echo ""
    echo -n "  选择 WAN 模式 [1-4]（默认 4）: "
    read -r wan_choice
    case "$wan_choice" in
        1) DIY_WAN_PROTO="dhcp"; DIY_WAN_CUSTOM="n" ;;
        2)
            DIY_WAN_PROTO="pppoe"
            DIY_WAN_CUSTOM="y"
            echo -n "  PPPoE 用户名: "
            read -r DIY_PPPOE_USER
            echo -n "  PPPoE 密码: "
            read -r -s DIY_PPPOE_PASS
            echo ""
            ;;
        3)
            DIY_WAN_PROTO="static"
            DIY_WAN_CUSTOM="y"
            echo -n "  WAN IP 地址: "
            read -r DIY_WAN_IP
            echo -n "  子网掩码（如 255.255.255.0）: "
            read -r DIY_WAN_MASK
            echo -n "  WAN 网关: "
            read -r DIY_WAN_GW
            ;;
        *) DIY_WAN_PROTO=""; DIY_WAN_CUSTOM="n" ;;
    esac

    # --- 防火墙设置 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【3. 防火墙设置】${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 默认防火墙（推荐）"
    echo -e "  ${CYAN} 2)${NC} 开放所有端口（仅用于测试，${RED}不安全${NC}）"
    echo -e "  ${CYAN} 3)${NC} 自定义入站规则"
    echo -e "  ${CYAN} 4)${NC} 仅允许特定 IP 访问 LuCI（${GREEN}安全${NC}）"
    echo ""
    echo -n "  选择 [1-4]（默认 1）: "
    read -r fw_choice
    case "$fw_choice" in
        2) DIY_FW_MODE="open" ;;
        3)
            DIY_FW_MODE="custom"
            echo -n "  要开放的端口（空格分隔，如 22 80 443）: "
            read -r DIY_FW_PORTS
            ;;
        4)
            DIY_FW_MODE="ip_whitelist"
            echo -n "  允许访问 LuCI 的 IP（如 192.168.1.100）: "
            read -r DIY_LUCI_IP
            ;;
        *) DIY_FW_MODE="default" ;;
    esac

    # --- LED 行为 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【4. LED 指示灯行为】${NC}"
    echo -e "  ${CYAN}适用于实体路由器，x86 虚拟机无效${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 默认行为（系统自带）"
    echo -e "  ${CYAN} 2)${NC} 全部熄灭"
    echo -e "  ${CYAN} 3)${NC} 常亮"
    echo -e "  ${CYAN} 4)${NC} 跟随系统状态（心跳闪烁）"
    echo -e "  ${CYAN} 5)${NC} 跳过"
    echo ""
    echo -n "  选择 [1-5]（默认 1）: "
    read -r led_choice
    case "$led_choice" in
        2) DIY_LED="off" ;;
        3) DIY_LED="on" ;;
        4) DIY_LED="heartbeat" ;;
        5) DIY_LED="" ;;
        *) DIY_LED="default" ;;
    esac

    # --- 内核模块定制 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【5. 内核/驱动模块定制】${NC}"
    echo -e "  ${CYAN}选择需要额外编译进固件的内核模块${NC}"
    echo ""
    echo -e "  ${YELLOW}存储/磁盘:${NC}"
    echo -e "   a) USB 存储（usb-storage + ext4/fat/ntfs）"
    echo -e "   b) NVMe SSD 支持"
    echo -e "   c) eSATA 支持"
    echo -e "   d) 自动挂载热插拔（block-mount + automount）"
    echo ""
    echo -e "  ${YELLOW}网络:${NC}"
    echo -e "   e) WireGuard 内核模块"
    echo -e "   f) VLAN 支持（802.1Q）"
    echo -e "   g) 硬件 NAT 加速（Flow Offload）"
    echo -e "   h) IPv6 支持（默认已启用）"
    echo ""
    echo -e "  ${YELLOW}虚拟化/容器:${NC}"
    echo -e "   i) KVM 虚拟化支持（内核模块）"
    echo -e "   j) Docker 支持（内核模块 + cgroups）"
    echo ""
    echo -e "  ${YELLOW}其他:${NC}"
    echo -e "   k) 音频驱动（USB 声卡）"
    echo -e "   l) 打印机支持（USB 打印 + p910nd）"
    echo ""
    echo -e "  ${CYAN}  q)${NC} 跳过"
    echo ""
    echo -n "  选择（可多选，空格分隔）: "
    read -r kernel_choices
    DIY_KERNEL_MODULES=""
    local kernel_map="a:kmod-usb-storage kmod-fs-ext4 kmod-fs-vfat kmod-fs-ntfs3 b:kmod-nvme c:kmod-ata-core d:block-mount e:kmod-wireguard f:kmod-8021q g:kmod-nft-offload h:CONFIG_IPV6=y i:kmod-kvm j:kmod-docker l:linux-util p910nd k:soundcore kmod-usb-audio l:kmod-usb-printer p910nd"
    for c in $kernel_choices; do
        for entry in $kernel_map; do
            local key="${entry%%:*}"
            local val="${entry##*:}"
            if [[ "$c" == "$key" ]]; then
                DIY_KERNEL_MODULES="${DIY_KERNEL_MODULES} ${val}"
                break
            fi
        done
    done
    [[ -z "$DIY_KERNEL_MODULES" ]] && DIY_KERNEL_MODULES="none"

    # --- 分区方案（x86 适用） ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【6. 磁盘分区方案】${NC}"
    echo -e "  ${CYAN}适用于 x86/64 虚拟化环境和带硬盘的路由器${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} squashfs（默认，支持刷机重置）"
    echo -e "  ${CYAN} 2)${NC} ext4（数据分区可扩展，推荐 SSD）"
    echo -e "  ${CYAN} 3)${NC} 组合模式（squashfs + ext4 overlay）"
    echo -e "  ${CYAN} 4)${NC} 跳过"
    echo ""
    echo -n "  选择 [1-4]（默认 1）: "
    read -r part_choice
    case "$part_choice" in
        2) DIY_TARGET_ROOTFS="ext4" ;;
        3) DIY_TARGET_ROOTFS="squashfs+ext4" ;;
        *) DIY_TARGET_ROOTFS="squashfs" ;;
    esac

    # --- SSH 设置 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【7. SSH 服务设置】${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 默认（Dropbear，端口 22）"
    echo -e "  ${CYAN} 2)${NC} OpenSSH（功能更全）"
    echo -e "  ${CYAN} 3)${NC} 自定义端口"
    echo -e "  ${CYAN} 4)${NC} 禁用 root 密码登录（仅密钥，${GREEN}安全${NC}）"
    echo -e "  ${CYAN} 5)${NC} 跳过"
    echo ""
    echo -n "  选择（可多选，空格分隔）: "
    read -r ssh_choices
    DIY_SSH_DROPBEAR="y"
    DIY_SSH_PORT="22"
    DIY_SSH_KEY_ONLY="n"
    for c in $ssh_choices; do
        case "$c" in
            2) DIY_SSH_DROPBEAR="n" ;;
            3)
                echo -n "  SSH 端口（默认 22）: "
                read -r DIY_SSH_PORT
                DIY_SSH_PORT="${DIY_SSH_PORT:-22}"
                ;;
            4) DIY_SSH_KEY_ONLY="y" ;;
        esac
    done

    # --- LuCI 访问设置 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【8. LuCI Web 界面设置】${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 默认 HTTP（端口 80）"
    echo -e "  ${CYAN} 2)${NC} 启用 HTTPS（自动生成证书）"
    echo -e "  ${CYAN} 3)${NC} 同时启用 HTTP + HTTPS"
    echo -e "  ${CYAN} 4)${NC} 跳过"
    echo ""
    echo -n "  选择 [1-4]（默认 1）: "
    read -r luci_choice
    case "$luci_choice" in
        2) DIY_LUCI_HTTPS="https_only" ;;
        3) DIY_LUCI_HTTPS="both" ;;
        *) DIY_LUCI_HTTPS="http" ;;
    esac

    # --- 禁用/启用服务 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【9. 默认启用/禁用服务】${NC}"
    echo ""
    echo -e "  ${YELLOW}以下服务在固件中会预装，可设置默认启用或禁用：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 禁用 Logd 日志写入磁盘（减少 SSD 写入）"
    echo -e "  ${CYAN} 2)${NC} 启用 Logd 写入 RAM"
    echo -e "  ${CYAN} 3)${NC} 禁用 Cron 定时任务"
    echo -e "  ${CYAN} 4)${NC} 禁用 Wan DNS 侦听（防止被探测）"
    echo -e "  ${CYAN} 5)${NC} 启用 AdGuard Home（需 feeds）"
    echo ""
    echo -n "  选择（可多选，空格分隔，留空跳过）: "
    read -r svc_choices
    DIY_SVC_CONFIG="$svc_choices"

    # --- 自定义文件/脚本注入 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【10. 自定义文件/脚本注入】${NC}"
    echo -e "  ${CYAN}可以将自定义文件或脚本写入固件指定位置${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 添加自定义 /etc/rc.local 启动脚本"
    echo -e "  ${CYAN} 2)${NC} 添加自定义 /etc/config/ 配置文件"
    echo -e "  ${CYAN} 3)${NC} 跳过"
    echo ""
    echo -n "  选择 [1-3]（默认 3）: "
    read -r inject_choice
    case "$inject_choice" in
        1)
            echo -e "  ${YELLOW}请输入 rc.local 中要执行的命令（输入 END 结束）：${NC}"
            DIY_RC_LOCAL=""
            while IFS= read -r line; do
                [[ "$line" == "END" ]] && break
                DIY_RC_LOCAL="${DIY_RC_LOCAL}${line}"$'\n'
            done
            ;;
        2)
            echo -n "  配置文件名（如 network，将写入 /etc/config/network）: "
            read -r DIY_CUSTOM_CFG_NAME
            if [[ -n "$DIY_CUSTOM_CFG_NAME" ]]; then
                echo -e "  ${YELLOW}请输入配置内容（输入 END 结束）：${NC}"
                DIY_CUSTOM_CFG_CONTENT=""
                while IFS= read -r line; do
                    [[ "$line" == "END" ]] && break
                    DIY_CUSTOM_CFG_CONTENT="${DIY_CUSTOM_CFG_CONTENT}${line}"$'\n'
                done
            fi
            ;;
    esac

    # --- 版本差异自动适配说明 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}【版本差异自动适配】${NC}"
    echo -e "  ${GREEN}以下设置将根据版本自动调整：${NC}"
    echo ""
    if [[ -n "$iw_version" ]]; then
        echo -e "  ${BLUE}当前源码：${NC}${iw_version}"
        # 根据版本给出提示
        if [[ "$iw_version" == *"24."* ]] || [[ "$iw_version" == *"25."* ]] || [[ "$iw_version" == *"master"* ]]; then
            echo -e "  ${GREEN}• 新版本：${NC}默认使用 nftables 防火墙，uhttpd→uhttpd或nginx"
            echo -e "  ${GREEN}• 新版本：${NC}支持 kernel 6.x，WireGuard 已内建"
        elif [[ "$iw_version" == *"23."* ]]; then
            echo -e "  ${GREEN}• 23.x：${NC}使用 nftables + DSA 网络架构"
        else
            echo -e "  ${GREEN}• 较旧版本：${NC}可能使用 iptables + swconfig 网络架构"
        fi
    fi
    echo -e "  ${GREEN}• WiFi 配置：${NC}自动检测 radio 数量（1/2），仅配置存在的 radio"
    echo -e "  ${GREEN}• 主题：${NC}自动检测可用主题，不存在则跳过"
    echo -e "  ${GREEN}• 语言包：${NC}自动匹配当前版本可用的语言包"

    # --- 追加保存到配置文件 ---
    echo ""
    sep_s
    echo -e "  ${BOLD}保存高级 DIY 配置...${NC}"

    cat >> "$DIY_SETTINGS_FILE" <<EOF

# ==== 高级设置 ====
# 用户名
DIY_USERNAME="${DIY_USERNAME:-root}"
# WAN
DIY_WAN_PROTO="${DIY_WAN_PROTO:-}"
DIY_WAN_CUSTOM="${DIY_WAN_CUSTOM:-n}"
DIY_PPPOE_USER="${DIY_PPPOE_USER:-}"
DIY_PPPOE_PASS="${DIY_PPPOE_PASS:-}"
DIY_WAN_IP="${DIY_WAN_IP:-}"
DIY_WAN_MASK="${DIY_WAN_MASK:-}"
DIY_WAN_GW="${DIY_WAN_GW:-}"
# 防火墙
DIY_FW_MODE="${DIY_FW_MODE:-default}"
DIY_FW_PORTS="${DIY_FW_PORTS:-}"
DIY_LUCI_IP="${DIY_LUCI_IP:-}"
# LED
DIY_LED="${DIY_LED:-default}"
# 内核模块
DIY_KERNEL_MODULES="${DIY_KERNEL_MODULES:-none}"
# 分区
DIY_TARGET_ROOTFS="${DIY_TARGET_ROOTFS:-squashfs}"
# SSH
DIY_SSH_DROPBEAR="${DIY_SSH_DROPBEAR:-y}"
DIY_SSH_PORT="${DIY_SSH_PORT:-22}"
DIY_SSH_KEY_ONLY="${DIY_SSH_KEY_ONLY:-n}"
# LuCI
DIY_LUCI_HTTPS="${DIY_LUCI_HTTPS:-http}"
# 服务
DIY_SVC_CONFIG="${DIY_SVC_CONFIG:-}"
# 注入
DIY_RC_LOCAL="${DIY_RC_LOCAL:-}"
DIY_CUSTOM_CFG_NAME="${DIY_CUSTOM_CFG_NAME:-}"
DIY_CUSTOM_CFG_CONTENT="${DIY_CUSTOM_CFG_CONTENT:-}"
EOF

    ok "高级 DIY 配置已追加保存到 ${DIY_SETTINGS_FILE}"
    echo ""
    echo -e "  ${GREEN}${BOLD}● 高级 DIY 配置完成！${NC}"
    echo -e "  ${CYAN}使用菜单 24 一键应用到源码${NC}"
    echo -e "  ${CYAN}使用菜单 23 快速应用预设方案${NC}"

    sep
}

#-------------------- 功能 23：DIY 预设方案 --------------------
diy_preset_template() {
    sep
    echo -e "${BOLD}          DIY 预设方案（快速模板）${NC}"
    sep
    echo ""

    mkdir -p "$DIY_CONFIG_DIR"

    echo -e "  ${BOLD}选择预设方案：${NC}"
    echo ""
    echo -e "  ${CYAN}【家庭路由方案】${NC}"
    echo -e "  ${CYAN} 1)${NC} ${GREEN}家庭路由标准版${NC}（中文+密码+WAN DHCP+防火墙+常用工具）"
    echo -e "  ${CYAN} 2)${NC} ${GREEN}家庭路由高级版${NC}（标准+PPPoE+IPv6+QoS+UPnP）"
    echo -e "  ${CYAN} 3)${NC} ${GREEN}旁路由/软路由版${NC}（中文+无WAN+静态IP+Argon主题）"
    echo ""
    echo -e "  ${CYAN}【开发/测试方案】${NC}"
    echo -e "  ${CYAN} 4)${NC} ${YELLOW}开发测试版${NC}（SSH OpenSSH+TTYD+全部工具+开放防火墙）"
    echo -e "  ${CYAN} 5)${NC} ${YELLOW}Docker 主机版${NC}（x86+Docker支持+磁盘管理+大存储）"
    echo -e "  ${CYAN} 6)${NC} ${YELLOW}全功能旗舰版${NC}（全部可用功能+全部推荐软件）"
    echo ""
    echo -e "  ${CYAN}【极简方案】${NC}"
    echo -e "  ${CYAN} 7)${NC} ${BOLD}纯净原版${NC}（仅中文语言，其余全部保持默认）"
    echo ""
    echo -e "  ${CYAN} 8)${NC} 查看各方案详情对比"
    echo -e "  ${CYAN} 0)${NC} 返回"
    echo ""
    echo -n "请选择: "
    read -r preset_choice

    case "$preset_choice" in
        1) diy_apply_preset "home_standard" ;;
        2) diy_apply_preset "home_advanced" ;;
        3) diy_apply_preset "bypass_router" ;;
        4) diy_apply_preset "dev_testing" ;;
        5) diy_apply_preset "docker_host" ;;
        6) diy_apply_preset "full_featured" ;;
        7) diy_apply_preset "minimal_cn" ;;
        8) diy_show_preset_compare ;;
        *) return ;;
    esac
}

#-------------------- 预设方案详情对比 --------------------
diy_show_preset_compare() {
    sep
    echo -e "${BOLD}          预设方案详情对比${NC}"
    sep
    echo ""

    printf "  ${BOLD}%-20s %-16s %-14s %-14s %-14s${NC}\n" "方案" "语言" "WiFi" "防火墙" "软件包数"
    echo -e "  ${BLUE}────────────────── ──────────────── ────────────── ────────────── ──────────────${NC}"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "1 家庭标准版" "中文简体" "配置" "默认" "9个"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "2 家庭高级版" "中文简体" "配置" "IPv6+QoS" "12个"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "3 旁路由版" "中文简体" "跳过" "默认" "8个"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "4 开发测试版" "中文简体" "跳过" "开放" "10个"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "5 Docker主机版" "中文简体" "跳过" "默认" "11个"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "6 全功能旗舰版" "中文简体" "配置" "IP白名单" "16+"
    printf "  %-20s %-16s %-14s %-14s %-14s\n" "7 纯净原版" "中文简体" "默认" "默认" "0"
    echo ""

    echo -e "  ${CYAN}各方案详细配置：${NC}"
    echo ""
    echo -e "  ${BOLD}1. 家庭路由标准版${NC}"
    echo -e "    语言: zh_cn | IP: 192.168.1.1 | 密码: 自设 | WiFi: 配置"
    echo -e "    DNS: 223.5.5.5/119.29.29.29 | 时区: CST-8 | 主题: Argon"
    echo -e "    软件: UPnP + TTYD + 文件管理 + opkg + 网络负载均衡 + WireGuard + 磁盘管理"
    echo ""
    echo -e "  ${BOLD}2. 家庭路由高级版${NC}"
    echo -e "    在标准版基础上 + IPv6启用 + QoS流量控制 + 在线升级 + SSH增强"
    echo ""
    echo -e "  ${BOLD}3. 旁路由/软路由版${NC}"
    echo -e "    语言: zh_cn | IP: 192.168.1.2 | 无WAN | 无WiFi | 主题: Argon"
    echo -e "    DNS: 223.5.5.5/119.29.29.29 | 软件: UPnP + TTYD + opkg + WireGuard"
    echo ""
    echo -e "  ${BOLD}4. 开发测试版${NC}"
    echo -e "    SSH: OpenSSH+自定义端口 | 防火墙: 全开放 | 端口: 22/80/443/8080"
    echo -e "    软件: 全部工具 + USB存储 + Docker内核支持"
    echo ""
    echo -e "  ${BOLD}5. Docker 主机版${NC}"
    echo -e "    x86 专用 | ext4分区 | 交换分区优化 | Docker管理LuCI"
    echo -e "    软件: 磁盘管理 + Docker + WireGuard + USB存储 + NVMe"
    echo ""
    echo -e "  ${BOLD}6. 全功能旗舰版${NC}"
    echo -e "    全部高级设置 | SSH密钥登录+IP白名单 | 全部工具包"
    echo -e "    自动挂载+IPv6+组播+热插拔+音频+打印"
    echo ""
    echo -e "  ${BOLD}7. 纯净原版${NC}"
    echo -e "    仅中文语言包，其余全部保持官方默认值"

    sep
}

#-------------------- 应用预设方案 --------------------
diy_apply_preset() {
    local preset=$1
    echo ""
    echo -e "  ${BOLD}应用预设方案：${NC}${preset}"

    echo -n "  请设置 Root 密码（留空=无密码）: "
    read -r -s preset_pass
    echo ""

    case "$preset" in
        home_standard)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.1"
            DIY_ROOT_PASS="$preset_pass"
            DIY_HOSTNAME="ImmortalWrt"
            DIY_TZ="CST-8"
            DIY_DNS1="223.5.5.5"
            DIY_DNS2="119.29.29.29"
            DIY_WIFI_ENABLED="y"
            DIY_SSID_24G="ImmortalWrt"
            DIY_SSID_5G="ImmortalWrt_5G"
            DIY_WIFI_PASS="12345678"
            DIY_THEME="argon"
            DIY_EXTRA_PKGS="luci-app-upnp luci-app-ttyd luci-app-filemanager luci-app-opkg luci-app-nlbw luci-app-wireguard luci-app-diskman"
            DIY_USERNAME="root"
            DIY_WAN_PROTO="dhcp"
            DIY_FW_MODE="default"
            DIY_SSH_DROPBEAR="y"
            DIY_SSH_PORT="22"
            DIY_TARGET_ROOTFS="squashfs"
            DIY_LUCI_HTTPS="http"
            ;;
        home_advanced)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.1"
            DIY_ROOT_PASS="$preset_pass"
            DIY_HOSTNAME="ImmortalWrt"
            DIY_TZ="CST-8"
            DIY_DNS1="223.5.5.5"
            DIY_DNS2="119.29.29.29"
            DIY_WIFI_ENABLED="y"
            DIY_SSID_24G="ImmortalWrt"
            DIY_SSID_5G="ImmortalWrt_5G"
            DIY_WIFI_PASS="12345678"
            DIY_THEME="argon"
            DIY_EXTRA_PKGS="luci-app-upnp luci-app-ttyd luci-app-filemanager luci-app-opkg luci-app-nlbw luci-app-sqm luci-app-attendedsysupgrade luci-app-wireguard luci-app-diskman luci-i18n-firewall-zh-cn luci-i18n-opkg-zh-cn"
            DIY_BOOT_EXTRAS="1 3"
            DIY_USERNAME="root"
            DIY_WAN_PROTO="dhcp"
            DIY_FW_MODE="default"
            DIY_SSH_DROPBEAR="y"
            DIY_SSH_PORT="22"
            DIY_TARGET_ROOTFS="squashfs"
            DIY_LUCI_HTTPS="http"
            ;;
        bypass_router)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.2"
            DIY_ROOT_PASS="$preset_pass"
            DIY_HOSTNAME="ImmortalWrt-Bypass"
            DIY_TZ="CST-8"
            DIY_DNS1="223.5.5.5"
            DIY_DNS2="119.29.29.29"
            DIY_WIFI_ENABLED="n"
            DIY_SSID_24G=""
            DIY_SSID_5G=""
            DIY_WIFI_PASS=""
            DIY_THEME="argon"
            DIY_EXTRA_PKGS="luci-app-upnp luci-app-ttyd luci-app-opkg luci-app-wireguard"
            DIY_USERNAME="root"
            DIY_WAN_PROTO=""
            DIY_FW_MODE="default"
            DIY_SSH_DROPBEAR="y"
            DIY_SSH_PORT="22"
            DIY_TARGET_ROOTFS="squashfs"
            DIY_LUCI_HTTPS="http"
            ;;
        dev_testing)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.1"
            DIY_ROOT_PASS="$preset_pass"
            DIY_HOSTNAME="ImmortalWrt-Dev"
            DIY_TZ="CST-8"
            DIY_DNS1="8.8.8.8"
            DIY_DNS2="1.1.1.1"
            DIY_WIFI_ENABLED="n"
            DIY_SSID_24G=""
            DIY_SSID_5G=""
            DIY_WIFI_PASS=""
            DIY_THEME="design"
            DIY_EXTRA_PKGS="luci-app-ttyd luci-app-filemanager luci-app-opkg luci-app-wireguard luci-app-diskman luci-app-docker"
            DIY_KERNEL_MODULES="kmod-usb-storage kmod-fs-ext4 kmod-fs-vfat"
            DIY_USERNAME="root"
            DIY_WAN_PROTO="dhcp"
            DIY_FW_MODE="open"
            DIY_SSH_DROPBEAR="n"
            DIY_SSH_PORT="22"
            DIY_TARGET_ROOTFS="ext4"
            DIY_LUCI_HTTPS="both"
            ;;
        docker_host)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.1"
            DIY_ROOT_PASS="$preset_pass"
            DIY_HOSTNAME="ImmortalWrt-Docker"
            DIY_TZ="CST-8"
            DIY_DNS1="223.5.5.5"
            DIY_DNS2="119.29.29.29"
            DIY_WIFI_ENABLED="n"
            DIY_SSID_24G=""
            DIY_SSID_5G=""
            DIY_WIFI_PASS=""
            DIY_THEME="argon"
            DIY_EXTRA_PKGS="luci-app-docker luci-app-diskman luci-app-ttyd luci-app-opkg luci-app-wireguard luci-app-filemanager"
            DIY_KERNEL_MODULES="kmod-usb-storage kmod-fs-ext4 kmod-fs-vfat kmod-nvme kmod-ata-core block-mount"
            DIY_USERNAME="root"
            DIY_WAN_PROTO="dhcp"
            DIY_FW_MODE="default"
            DIY_SSH_DROPBEAR="y"
            DIY_SSH_PORT="22"
            DIY_TARGET_ROOTFS="ext4"
            DIY_LUCI_HTTPS="http"
            ;;
        full_featured)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.1"
            DIY_ROOT_PASS="$preset_pass"
            DIY_HOSTNAME="ImmortalWrt"
            DIY_TZ="CST-8"
            DIY_DNS1="223.5.5.5"
            DIY_DNS2="119.29.29.29"
            DIY_WIFI_ENABLED="y"
            DIY_SSID_24G="ImmortalWrt"
            DIY_SSID_5G="ImmortalWrt_5G"
            DIY_WIFI_PASS="12345678"
            DIY_THEME="argon"
            DIY_EXTRA_PKGS="luci-app-upnp luci-app-ttyd luci-app-filemanager luci-app-opkg luci-app-nlbw luci-app-sqm luci-app-attendedsysupgrade luci-app-wireguard luci-app-diskman luci-app-docker luci-i18n-firewall-zh-cn luci-i18n-opkg-zh-cn"
            DIY_KERNEL_MODULES="kmod-usb-storage kmod-fs-ext4 kmod-fs-vfat kmod-fs-ntfs3 block-mount kmod-wireguard kmod-8021q kmod-nft-offload"
            DIY_BOOT_EXTRAS="1 3"
            DIY_USERNAME="root"
            DIY_WAN_PROTO="dhcp"
            DIY_FW_MODE="ip_whitelist"
            DIY_LUCI_IP="192.168.1.100"
            DIY_SSH_DROPBEAR="y"
            DIY_SSH_PORT="22"
            DIY_SSH_KEY_ONLY="y"
            DIY_TARGET_ROOTFS="squashfs"
            DIY_LUCI_HTTPS="https_only"
            ;;
        minimal_cn)
            DIY_LANG="zh_cn"
            DIY_LAN_IP="192.168.1.1"
            DIY_ROOT_PASS=""
            DIY_HOSTNAME="ImmortalWrt"
            DIY_TZ="CST-8"
            DIY_DNS1=""
            DIY_DNS2=""
            DIY_WIFI_ENABLED="n"
            DIY_SSID_24G=""
            DIY_SSID_5G=""
            DIY_WIFI_PASS=""
            DIY_THEME=""
            DIY_EXTRA_PKGS=""
            DIY_USERNAME="root"
            DIY_WAN_PROTO=""
            DIY_FW_MODE="default"
            DIY_SSH_DROPBEAR="y"
            DIY_SSH_PORT="22"
            DIY_TARGET_ROOTFS="squashfs"
            DIY_LUCI_HTTPS="http"
            ;;
    esac

    DIY_EXTRA_PKG_LIST="${DIY_EXTRA_PKGS// /, }"
    DIY_BOOT_EXTRAS="${DIY_BOOT_EXTRAS:-}"
    DIY_HW_ENABLED="n"

    # 保存
    cat > "$DIY_SETTINGS_FILE" <<EOF
# ImmortalWrt DIY 定制配置（预设方案: ${preset}）
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 语言
DIY_LANG="${DIY_LANG}"
# IP
DIY_LAN_IP="${DIY_LAN_IP}"
# Root 密码
DIY_ROOT_PASS="${DIY_ROOT_PASS}"
# 主机名
DIY_HOSTNAME="${DIY_HOSTNAME}"
# 时区
DIY_TZ="${DIY_TZ}"
# DNS
DIY_DNS1="${DIY_DNS1:-223.5.5.5}"
DIY_DNS2="${DIY_DNS2:-119.29.29.29}"
# WiFi
DIY_WIFI_ENABLED="${DIY_WIFI_ENABLED}"
DIY_SSID_24G="${DIY_SSID_24G}"
DIY_SSID_5G="${DIY_SSID_5G}"
DIY_WIFI_PASS="${DIY_WIFI_PASS}"
# 主题
DIY_THEME="${DIY_THEME}"
# 额外软件包
DIY_EXTRA_PKGS="${DIY_EXTRA_PKGS}"
DIY_EXTRA_PKG_LIST="${DIY_EXTRA_PKG_LIST}"
# 开机配置
DIY_BOOT_EXTRAS="${DIY_BOOT_EXTRAS}"
DIY_CUSTOM_UCI=""
# 硬件
DIY_HW_ENABLED="${DIY_HW_ENABLED}"

# ==== 高级设置 ====
DIY_USERNAME="${DIY_USERNAME:-root}"
DIY_WAN_PROTO="${DIY_WAN_PROTO:-}"
DIY_WAN_CUSTOM="${DIY_WAN_CUSTOM:-n}"
DIY_PPPOE_USER="${DIY_PPPOE_USER:-}"
DIY_PPPOE_PASS="${DIY_PPPOE_PASS:-}"
DIY_WAN_IP="${DIY_WAN_IP:-}"
DIY_WAN_MASK="${DIY_WAN_MASK:-}"
DIY_WAN_GW="${DIY_WAN_GW:-}"
DIY_FW_MODE="${DIY_FW_MODE:-default}"
DIY_FW_PORTS="${DIY_FW_PORTS:-}"
DIY_LUCI_IP="${DIY_LUCI_IP:-}"
DIY_LED="${DIY_LED:-default}"
DIY_KERNEL_MODULES="${DIY_KERNEL_MODULES:-none}"
DIY_TARGET_ROOTFS="${DIY_TARGET_ROOTFS:-squashfs}"
DIY_SSH_DROPBEAR="${DIY_SSH_DROPBEAR:-y}"
DIY_SSH_PORT="${DIY_SSH_PORT:-22}"
DIY_SSH_KEY_ONLY="${DIY_SSH_KEY_ONLY:-n}"
DIY_LUCI_HTTPS="${DIY_LUCI_HTTPS:-http}"
DIY_SVC_CONFIG="${DIY_SVC_CONFIG:-}"
DIY_RC_LOCAL="${DIY_RC_LOCAL:-}"
DIY_CUSTOM_CFG_NAME="${DIY_CUSTOM_CFG_NAME:-}"
DIY_CUSTOM_CFG_CONTENT="${DIY_CUSTOM_CFG_CONTENT:-}"
EOF

    chmod 600 "$DIY_SETTINGS_FILE"

    ok "预设方案 [${preset}] 已应用"
    echo ""
    diy_show_summary

    echo ""
    echo -e "  ${GREEN}${BOLD}● 预设方案已就绪！${NC}"
    echo -e "  ${YELLOW}提示：${NC}"
    echo -e "  ${CYAN}  • 可继续使用菜单 22 补充高级设置${NC}"
    echo -e "  ${CYAN}  • 使用菜单 24 将配置应用到源码${NC}"

    sep
}

#-------------------- 功能 11：备份配置 --------------------
backup_config() {
    sep
    echo -e "${BOLD}          备份当前配置${NC}"
    sep
    echo ""

    if [[ ! -f "$SOURCE_DIR/.config" ]]; then
        warn "未找到 .config 文件"
        return
    fi

    mkdir -p "$CONFIG_BACKUP_DIR"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${CONFIG_BACKUP_DIR}/config_${timestamp}"

    cp "$SOURCE_DIR/.config" "$backup_file"
    ok "配置已备份: ${backup_file}"

    # 同时备份 feeds.conf
    if [[ -f "$SOURCE_DIR/feeds.conf" ]]; then
        cp "$SOURCE_DIR/feeds.conf" "${CONFIG_BACKUP_DIR}/feeds_${timestamp}"
        ok "feeds.conf 已备份"
    fi

    # 保留最近 20 个备份
    local count=$(ls -1 "$CONFIG_BACKUP_DIR"/config_* 2>/dev/null | wc -l)
    if [[ $count -gt 20 ]]; then
        ls -t "$CONFIG_BACKUP_DIR"/config_* | tail -n +21 | while read -r old; do
            rm -f "$old"
        done
        ok "已清理旧备份（保留最近 20 个）"
    fi

    sep
}

#-------------------- 功能 12：恢复配置 --------------------
restore_config() {
    sep
    echo -e "${BOLD}          恢复配置${NC}"
    sep
    echo ""

    if [[ ! -d "$CONFIG_BACKUP_DIR" ]] || [[ -z "$(ls "$CONFIG_BACKUP_DIR"/config_* 2>/dev/null)" ]]; then
        warn "暂无配置备份"
        return
    fi

    echo -e "  ${BOLD}可用备份：${NC}"
    echo ""

    local idx=1
    declare -A backup_map

    for f in $(ls -t "$CONFIG_BACKUP_DIR"/config_* 2>/dev/null); do
        local fname=$(basename "$f")
        local fdate=$(echo "$fname" | sed 's/config_//')
        echo -e "  ${CYAN}[$idx]${NC} ${fdate}"
        backup_map[$idx]="$f"
        idx=$((idx + 1))
    done

    echo ""
    echo -n "  输入要恢复的编号（或 Enter 取消）: "
    read -r restore_idx

    if [[ -z "$restore_idx" || -z "${backup_map[$restore_idx]}" ]]; then
        info "已取消"
        return
    fi

    local source="${backup_map[$restore_idx]}"
    cp "$source" "$SOURCE_DIR/.config"

    cd "$SOURCE_DIR"
    make defconfig

    ok "配置已恢复"

    sep
}

#-------------------- 功能 13：开始编译 --------------------
start_build() {
    sep
    echo -e "${BOLD}          开始编译${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    if [[ ! -f "$SOURCE_DIR/.config" ]]; then
        warn "未找到 .config，请先配置"
        return
    fi

    cd "$SOURCE_DIR"

    # 检测最佳线程数
    local threads=$((CPU_CORES + 1))
    if [[ "$TOTAL_MEM" -gt 0 ]] && [[ "$TOTAL_MEM" -lt 4 ]]; then
        threads=$CPU_CORES
        warn "内存较少，降低线程数为 ${threads}"
    fi

    echo -e "  ${BOLD}编译参数：${NC}"
    echo -e "  ${BLUE}线程数：${NC}${threads}（CPU ${CPU_CORES}核 + 1）"
    echo -e "  ${BLUE}内存  ：${NC}${TOTAL_MEM}GB"
    echo -e "  ${BLUE}V=sc  ：${NC}显示详细错误信息"
    echo ""

    echo -e "  ${BOLD}编译选项：${NC}"
    echo -e "  ${CYAN} 1)${NC} 标准编译（make -j${threads} V=sc）"
    echo -e "  ${CYAN} 2)${NC} 首次编译（先工具链再固件，更稳定）"
    echo -e "  ${CYAN} 3)${NC} 仅编译特定软件包"
    echo ""
    echo -n "请选择 [1-3]（默认 1）: "
    read -r build_choice
    build_choice="${build_choice:-1}"

    echo ""
    echo -e "  ${YELLOW}编译时间预计 1-4 小时，取决于 CPU 和网络${NC}"
    echo -e "  ${YELLOW}编译过程中请勿关闭终端${NC}"
    echo ""
    echo -n "  确认开始编译？(Y/n): "
    read -r confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return

    echo ""
    echo -e "${BOLD}开始编译...${NC}"
    echo ""

    # 记录开始时间
    local start_time=$(date +%s)

    case "$build_choice" in
        2)
            info "第一步：编译工具链..."
            make toolchain -j"$threads" V=sc 2>&1 | tee -a "$LOG_FILE"
            if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                ok "工具链编译完成"
                echo ""
                info "第二步：编译固件..."
                make -j"$threads" V=sc 2>&1 | tee -a "$LOG_FILE"
            else
                error "工具链编译失败"
                return
            fi
            ;;
        3)
            echo -n "  输入要编译的软件包名（如 luci-app-passwall）: "
            read -r pkg_name
            info "编译软件包: ${pkg_name}..."
            make package/"${pkg_name}"/compile -j"$threads" V=sc 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            info "开始完整编译..."
            make -j"$threads" V=sc 2>&1 | tee -a "$LOG_FILE"
            ;;
    esac

    local build_status=${PIPESTATUS[0]}
    local end_time=$(date +%s)
    local duration=$(( (end_time - start_time) / 60 ))

    echo ""

    if [[ $build_status -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}${BOLD}              ● 编译成功！${NC}"
        echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${BLUE}编译用时：${NC}${duration} 分钟"
        echo ""
        echo -e "  ${BOLD}固件位置：${NC}"
        find "${SOURCE_DIR}/bin/targets/" -name "*.img" -o -name "*.bin" -o -name "*.squashfs" 2>/dev/null | while read -r f; do
            local fsize=$(du -h "$f" | cut -f1)
            echo -e "  ${CYAN}${f}${NC} (${fsize})"
        done
    else
        echo -e "  ${RED}${BOLD}═══════════════════════════════════════════════${NC}"
        echo -e "  ${RED}${BOLD}              ● 编译失败！${NC}"
        echo -e "  ${RED}${BOLD}═══════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${BLUE}编译用时：${NC}${duration} 分钟"
        echo ""
        echo -e "  ${YELLOW}排查建议：${NC}"
        echo -e "  1. 查看完整日志: ${LOG_FILE}"
        echo -e "  2. 使用菜单 17 查看编译日志"
        echo -e "  3. 尝试单线程编译: make V=sc"
        echo -e "  4. 清理后重试: make dirclean && make -j${threads}"
        echo -e "  5. 检查网络和磁盘空间"
    fi

    sep
}

#-------------------- 功能 14：仅编译工具链 --------------------
build_toolchain_only() {
    sep
    echo -e "${BOLD}          仅编译工具链${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    local threads=$((CPU_CORES + 1))

    echo -e "  ${YELLOW}首次编译推荐先编译工具链，避免内存不足${NC}"
    echo -e "  ${YELLOW}工具链编译约需 30-60 分钟${NC}"
    echo ""
    echo -n "  确认编译工具链？(Y/n): "
    read -r confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return

    info "编译工具链（-j${threads}）..."
    make toolchain -j"$threads" V=sc 2>&1 | tee -a "$LOG_FILE"

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        ok "工具链编译成功"
        echo -e "  ${YELLOW}下一步：使用菜单 13 编译完整固件${NC}"
    else
        error "工具链编译失败，请查看日志"
    fi

    sep
}

#-------------------- 功能 15：后台编译 --------------------
background_build() {
    sep
    echo -e "${BOLD}          后台编译（nohup，可断开 SSH）${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    if [[ ! -f "$SOURCE_DIR/.config" ]]; then
        warn "未找到 .config，请先配置"
        return
    fi

    cd "$SOURCE_DIR"

    local threads=$((CPU_CORES + 1))
    local bg_log="${BUILD_HOME}/immortalwrt_nohup.log"

    echo -e "  ${BOLD}后台编译参数：${NC}"
    echo -e "  ${BLUE}线程数：${NC}${threads}"
    echo -e "  ${BLUE}日志  ：${NC}${bg_log}"
    echo ""
    echo -e "  ${GREEN}● 使用 nohup 后台运行，可安全断开 SSH${NC}"
    echo -e "  ${GREEN}● 编译完成后会在日志末尾显示结果${NC}"
    echo ""
    echo -n "  确认开始后台编译？(Y/n): "
    read -r confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return

    nohup bash -c "cd '$SOURCE_DIR' && make -j${threads} V=sc" > "$bg_log" 2>&1 &

    local pid=$!
    echo "$pid" > "${BUILD_HOME}/immortalwrt_build.pid"

    ok "后台编译已启动"
    echo -e "  ${BLUE}PID    ：${NC}${pid}"
    echo -e "  ${BLUE}日志   ：${NC}${bg_log}"
    echo ""
    echo -e "  ${YELLOW}常用命令：${NC}"
    echo -e "  ${CYAN}查看进度: tail -f ${bg_log}${NC}"
    echo -e "  ${CYAN}检查进程: ps aux | grep make${NC}"
    echo -e "  ${CYAN}停止编译: kill ${pid}${NC}"

    sep
}

#-------------------- 功能 16：清理编译 --------------------
clean_build() {
    sep
    echo -e "${BOLD}          清理编译${NC}"
    sep
    echo ""

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "源码目录不存在"
        return
    fi

    cd "$SOURCE_DIR"

    echo -e "  ${BOLD}选择清理级别：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} clean      ${YELLOW}（清理编译产物，保留配置和工具链）${NC}"
    echo -e "  ${CYAN} 2)${NC} dirclean   ${YELLOW}（彻底清理，保留配置，删除工具链）${NC}"
    echo -e "  ${CYAN} 3)${NC} distclean  ${RED}（完全清理，删除所有包括配置）${NC}"
    echo ""
    echo -n "请选择: "
    read -r clean_choice

    local clean_target=""
    case "$clean_choice" in
        1) clean_target="clean" ;;
        2) clean_target="dirclean" ;;
        3)
            warn "distclean 将删除 .config 和所有编译文件！"
            echo -n "  确认？(y/N): "
            read -r confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && return
            clean_target="distclean"
            ;;
        *) info "已取消"; return ;;
    esac

    info "执行 make ${clean_target}..."
    make "$clean_target"

    ok "清理完成"

    sep
}

#-------------------- 功能 17：查看编译日志 --------------------
show_build_log() {
    sep
    echo -e "${BOLD}          查看编译日志${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}选择日志：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 编译日志（最近 50 行）"
    echo -e "  ${CYAN} 2)${NC} 后台编译日志（实时跟踪）"
    echo -e "  ${CYAN} 3)${NC} 搜索错误信息"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            if [[ -f "$LOG_FILE" ]]; then
                tail -50 "$LOG_FILE"
            else
                warn "无编译日志"
            fi
            ;;
        2)
            local bg_log="${BUILD_HOME}/immortalwrt_nohup.log"
            if [[ -f "$bg_log" ]]; then
                info "实时跟踪后台编译日志（Ctrl+C 退出）..."
                tail -f "$bg_log"
            else
                warn "无后台编译日志"
            fi
            ;;
        3)
            local search_log="${LOG_FILE}"
            [[ -f "${BUILD_HOME}/immortalwrt_nohup.log" ]] && search_log="${BUILD_HOME}/immortalwrt_nohup.log"

            if [[ -f "$search_log" ]]; then
                echo -e "  ${BOLD}搜索错误信息...${NC}"
                echo ""
                grep -i -n "error\|failed\|fatal" "$search_log" | tail -30 || ok "未发现错误"
            else
                warn "无日志文件"
            fi
            ;;
    esac

    sep
}

#-------------------- 功能 18：查看编译产物 --------------------
show_artifacts() {
    sep
    echo -e "${BOLD}          查看编译产物${NC}"
    sep
    echo ""

    local bin_dir="${SOURCE_DIR}/bin"

    if [[ ! -d "$bin_dir" ]]; then
        warn "无编译产物目录"
        return
    fi

    echo -e "  ${BOLD}固件文件：${NC}"
    echo ""
    find "$bin_dir/targets/" -type f \( -name "*.img" -o -name "*.bin" -o -name "*.squashfs" -o -name "*.tar.gz" -o -name "*.manifest" \) 2>/dev/null | while read -r f; do
        local fsize=$(du -h "$f" | cut -f1)
        local fname=$(basename "$f")
        local relpath=${f#${bin_dir}/}
        echo -e "  ${CYAN}${fname}${NC} (${fsize})"
        echo -e "    ${BLUE}${relpath}${NC}"
    done

    echo ""
    echo -e "  ${BOLD}软件包（IPK）：${NC}"
    echo ""
    local ipk_count=$(find "$bin_dir/packages/" -name "*.ipk" 2>/dev/null | wc -l)
    if [[ "$ipk_count" -gt 0 ]]; then
        echo -e "  ${GREEN}共 ${ipk_count} 个软件包${NC}"
        echo ""
        find "$bin_dir/packages/" -name "*.ipk" 2>/dev/null | head -20 | while read -r f; do
            local fname=$(basename "$f")
            echo -e "  ${CYAN}${fname}${NC}"
        done
        [[ "$ipk_count" -gt 20 ]] && echo -e "  ${YELLOW}...还有 $((ipk_count - 20)) 个${NC}"
    else
        warn "无软件包"
    fi

    echo ""
    echo -e "  ${BOLD}目录大小：${NC}"
    du -sh "$bin_dir" 2>/dev/null

    sep
}

#-------------------- 功能 19：下载固件 --------------------
download_firmware() {
    sep
    echo -e "${BOLD}          下载固件到本地${NC}"
    sep
    echo ""

    local bin_dir="${SOURCE_DIR}/bin/targets"

    if [[ ! -d "$bin_dir" ]]; then
        warn "无编译产物"
        return
    fi

    # 列出固件文件
    local idx=1
    declare -A file_map

    echo -e "  ${BOLD}可用固件：${NC}"
    echo ""
    find "$bin_dir" -type f \( -name "*.img" -o -name "*.bin" -o -name "*.squashfs" \) 2>/dev/null | while read -r f; do
        local fsize=$(du -h "$f" | cut -f1)
        local fname=$(basename "$f")
        echo -e "  ${CYAN}[$idx]${NC} ${fname} (${fsize})"
    done

    echo ""
    echo -e "  ${BOLD}传输方式：${NC}"
    echo -e "  ${CYAN} 1)${NC} sz（Zmodem，需 lrzsz）"
    echo -e "  ${CYAN} 2)${NC} scp 命令提示"
    echo -e "  ${CYAN} 3)${NC} HTTP 下载（临时启动 HTTP 服务）"
    echo ""
    echo -n "请选择: "
    read -r transfer_choice

    case "$transfer_choice" in
        1)
            echo -n "  输入要下载的固件编号: "
            read -r file_idx
            local target_file="${file_map[$file_idx]}"
            if [[ -n "$target_file" ]] && command -v sz &>/dev/null; then
                sz "$target_file"
            else
                warn "sz 命令不可用，请安装: sudo apt install lrzsz"
            fi
            ;;
        2)
            local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            echo -e "  ${CYAN}在本地终端执行：${NC}"
            echo ""
            find "$bin_dir" -name "*.img" 2>/dev/null | head -5 | while read -r f; do
                echo -e "  scp ${BUILD_USER}@${server_ip}:${f} ."
            done
            ;;
        3)
            local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            local http_port=8000
            info "启动 HTTP 下载服务（端口 ${http_port}）..."
            echo -e "  ${CYAN}在浏览器访问: http://${server_ip}:${http_port}/${NC}"
            echo -e "  ${YELLOW}按 Ctrl+C 停止${NC}"
            echo ""
            cd "$bin_dir"
            python3 -m http.server "$http_port" 2>/dev/null
            ;;
    esac

    sep
}

#-------------------- 功能 20：常见问题 --------------------
show_faq() {
    sep
    echo -e "${BOLD}          常见问题与解决方案${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}${CYAN}Q1: 编译报错 "No space left on device"${NC}"
    echo -e "  ${YELLOW}A: 磁盘空间不足，至少需要 25GB。清理旧编译或扩大磁盘。${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q2: 编译报错 "g++: internal compiler error: Killed"${NC}"
    echo -e "  ${YELLOW}A: 内存不足导致进程被杀。${NC}"
    echo -e "  ${YELLOW}  解决：1) 添加 swap（菜单 3）${NC}"
    echo -e "  ${YELLOW}       2) 降低线程数：make -j1${NC}"
    echo -e "  ${YELLOW}       3) 先编译工具链：make toolchain${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q3: git clone 超时或失败${NC}"
    echo -e "  ${YELLOW}A: GitHub 网络问题。${NC}"
    echo -e "  ${YELLOW}  解决：1) 使用 ghproxy 加速（菜单 3）${NC}"
    echo -e "  ${YELLOW}       2) 配置 HTTP/SOCKS5 代理${NC}"
    echo -e "  ${YELLOW}       3) 使用 Gitee 镜像源${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q4: make menuconfig 报错${NC}"
    echo -e "  ${YELLOW}A: 缺少 ncurses 库。${NC}"
    echo -e "  ${YELLOW}  解决：sudo apt install libncurses-dev${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q5: WSL2 编译报路径错误${NC}"
    echo -e "  ${YELLOW}A: Windows 路径在 PATH 中干扰编译。${NC}"
    echo -e "  ${YELLOW}  解决：使用菜单 1 安装时自动配置，或手动编辑 ~/.bashrc${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q6: feeds 中找不到某个软件包${NC}"
    echo -e "  ${YELLOW}A: 需要添加额外的 feeds 源。${NC}"
    echo -e "  ${YELLOW}  解决：使用菜单 7 添加额外 feeds，然后执行菜单 8 更新${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q7: 编译出的固件无法启动${NC}"
    echo -e "  ${YELLOW}A: 配置不匹配。${NC}"
    echo -e "  ${YELLOW}  解决：1) 确认目标平台选择正确${NC}"
    echo -e "  ${YELLOW}       2) 检查内核模块是否齐全${NC}"
    echo -e "  ${YELLOW}       3) 尝试使用 defconfig 加载默认配置${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q8: 编译速度太慢${NC}"
    echo -e "  ${YELLOW}A: 优化方法：${NC}"
    echo -e "  ${YELLOW}  1) 增加线程数（但不超过 CPU 核心+1）${NC}"
    echo -e "  ${YELLOW}  2) 启用 ccache 缓存（菜单 3）${NC}"
    echo -e "  ${YELLOW}  3) 使用 SSD 而非 HDD${NC}"
    echo -e "  ${YELLOW}  4) 确保内存充足（4GB+）${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q9: 如何编译特定软件包而非整个固件${NC}"
    echo -e "  ${YELLOW}A: 使用菜单 13 选项 3，输入软件包名即可。${NC}"
    echo -e "  ${YELLOW}  或手动执行: make package/luci-app-xxx/compile V=sc${NC}"
    echo ""

    echo -e "  ${BOLD}${CYAN}Q10: 更新源码后编译报错${NC}"
    echo -e "  ${YELLOW}A: 源码结构变更。${NC}"
    echo -e "  ${YELLOW}  解决：make dirclean && ./scripts/feeds update -a && ./scripts/feeds install -a${NC}"
    echo -e "  ${YELLOW}       然后重新 menuconfig 和编译${NC}"

    sep
}

#-------------------- 主循环 --------------------
main() {
    check_not_root

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1) setup_build_env ;;
            2) check_system ;;
            3) optimize_virt_env ;;
            4) clone_source ;;
            5) update_source ;;
            6) switch_branch ;;
            7) add_extra_feeds ;;
            8) update_feeds ;;
            9) menu_config ;;
            10) load_preset_config ;;
            21) diy_settings ;;
            22) diy_advanced_settings ;;
            23) diy_preset_template ;;
            24) diy_preset_apply ;;
            25) diy_show_export ;;
            11) backup_config ;;
            12) restore_config ;;
            13) start_build ;;
            14) build_toolchain_only ;;
            15) background_build ;;
            16) clean_build ;;
            17) show_build_log ;;
            18) show_artifacts ;;
            19) download_firmware ;;
            20) show_faq ;;
            0|q|Q)
                echo ""
                info "退出 ImmortalWrt 编译脚本"
                echo ""
                exit 0
                ;;
            *)
                echo -e "  ${RED}无效选项，请重新选择${NC}"
                ;;
        esac

        echo ""
        echo -n "按 Enter 键返回主菜单..."
        read -r
    done
}

main