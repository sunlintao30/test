#!/bin/bash
#=============================================================================
# BBR 拥塞控制算法管理脚本
# 功能：安装 / 启用 / 禁用 / 状态查看 / 内核升级检测
# 支持：所有主流 Linux 发行版
# 用法：chmod +x bbr_manager.sh && sudo ./bbr_manager.sh
#=============================================================================

set -e

#-------------------- 颜色定义 --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

#-------------------- 辅助函数 --------------------
info()     { echo -e "${GREEN}[信息]${NC} $*"; }
warn()     { echo -e "${YELLOW}[警告]${NC} $*"; }
error()    { echo -e "${RED}[错误]${NC} $*"; }
ok()       { echo -e "${GREEN}  ✓${NC} $*"; }
fail()     { echo -e "${RED}  ✗${NC} $*"; }
sep()      { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

needs_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本：sudo $0"
    fi
}

#-------------------- 显示菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}          BBR 拥塞控制算法 - 管理脚本${NC}"
    sep
    echo ""
    echo -e "  ${CYAN} 1)${NC} 查看 BBR 当前状态"
    echo -e "  ${CYAN} 2)${NC} 启用 BBR"
    echo -e "  ${CYAN} 3)${NC} 禁用 BBR（恢复默认 CUBIC）"
    echo -e "  ${CYAN} 4)${NC} 内核版本检测 & 升级建议"
    echo -e "  ${CYAN} 5)${NC} 编译安装最新内核（含 BBR）"
    echo -e "  ${CYAN} 6)${NC} BBR 参数调优"
    echo -e "  ${CYAN} 7)${NC} 网络性能测试（BBR vs 默认）"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n ""
    echo -n "请输入选项: "
}

#-------------------- 获取内核信息 --------------------
get_kernel_version() {
    local version
    version=$(uname -r)
    echo "$version"
}

get_kernel_major() {
    local major minor
    read -r major minor _ <<< "$(get_kernel_version | sed 's/[^0-9].*/ /g' | tr '.' ' ')"
    echo "${major}.${minor}"
}

#-------------------- 功能 1：查看状态 --------------------
bbr_status() {
    sep
    echo -e "${BOLD}          BBR 状态总览${NC}"
    sep
    echo ""

    local kernel_ver=$(get_kernel_version)
    echo -e "  ${BLUE}内核版本：${NC}${kernel_ver}"

    # 内核版本检查
    local major=$(echo "$kernel_ver" | cut -d. -f1)
    local minor=$(echo "$kernel_ver" | cut -d. -f2)

    if [[ "$major" -lt 4 ]] || [[ "$major" -eq 4 && "$minor" -lt 9 ]]; then
        fail "内核版本低于 4.9，BBR 不可用"
        echo ""
        return 1
    else
        ok "内核版本满足 BBR 最低要求 (>= 4.9)"
    fi

    echo ""

    # 检查 BBR 模块是否加载
    echo -e "  ${BLUE}内核模块：${NC}"
    if lsmod | grep -q "tcp_bbr"; then
        ok "tcp_bbr 模块已加载"
    else
        # 检查是否编译进内核
        if grep -q "CONFIG_TCP_CONG_BBR=y" /boot/config-$(uname -r) 2>/dev/null; then
            ok "tcp_bbr 已编译进内核（非模块模式）"
        elif grep -q "CONFIG_TCP_CONG_BBR=m" /boot/config-$(uname -r) 2>/dev/null; then
            warn "tcp_bbr 模块存在但未加载"
        else
            if [[ "$major" -ge 4 && "$minor" -ge 9 ]]; then
                warn "tcp_bbr 模块未加载（尝试加载中...）"
                modprobe tcp_bbr 2>/dev/null && ok "模块加载成功" || fail "模块加载失败"
            else
                fail "tcp_bbr 模块不可用"
            fi
        fi
    fi

    echo ""

    # 可用拥塞控制算法
    echo -e "  ${BLUE}可用算法：${NC}"
    local available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
    if [[ -n "$available" ]]; then
        echo -e "    ${CYAN}${available}${NC}"
    else
        warn "无法获取可用算法列表"
    fi

    echo ""

    # 当前拥塞控制算法
    echo -e "  ${BLUE}当前算法：${NC}"
    local current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$current" == "bbr" ]]; then
        echo -e "    ${GREEN}${BOLD}bbr${NC} ${GREEN}← 已启用${NC}"
    else
        echo -e "    ${YELLOW}${current}${NC} ${YELLOW}← 未启用 BBR${NC}"
    fi

    echo ""

    # 默认队列规则
    echo -e "  ${BLUE}队列规则（qdisc）：${NC}"
    local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [[ "$qdisc" == "fq" ]]; then
        echo -e "    ${GREEN}fq${NC} ${GREEN}← 推荐值（与 BBR 最佳配合）${NC}"
    else
        echo -e "    ${YELLOW}${qdisc}${NC} ${YELLOW}← 建议改为 fq 以获得最佳效果${NC}"
    fi

    echo ""

    # 各网卡队列规则
    echo -e "  ${BLUE}网卡队列规则：${NC}"
    for nic in $(ip link show | grep -E "^[0-9]" | awk -F: '{print $2}' | tr -d ' '); do
        local nic_qdisc=$(tc qdisc show dev "$nic" 2>/dev/null | head -1 | awk '{print $3}')
        if [[ -n "$nic_qdisc" ]]; then
            echo -e "    ${CYAN}${nic}${NC}: ${nic_qdisc}"
        fi
    done

    echo ""

    # BBR 详细参数
    echo -e "  ${BLUE}BBR 参数：${NC}"
    if [[ -f /proc/sys/net/ipv4/tcp_bbr_bw_probe_bw_gain ]]; then
        # BBRv2/v3 参数
        echo -e "    检测到 BBRv2/v3 高级参数："
        local params=(
            "net.ipv4.tcp_bbr_bw_probe_bw_gain"
            "net.ipv4.tcp_bbr_bw_probe_rtt_gain"
            "net.ipv4.tcp_bbr_cwnd_gain"
            "net.ipv4.tcp_bbr_cwnd_min_gain"
            "net.ipv4.tcp_bbr_pacing_gain"
            "net.ipv4.tcp_bbr_probe_rtt_gain"
        )
        for p in "${params[@]}"; do
            local val=$(sysctl -n "$p" 2>/dev/null)
            if [[ -n "$val" ]]; then
                echo -e "    ${CYAN}$(echo "$p" | sed 's/net.ipv4.tcp_bbr_//')${NC} = ${val}"
            fi
        done
    else
        echo -e "    当前为 BBRv1（基础参数，无可调项）"
    fi

    echo ""

    # 总结
    if [[ "$current" == "bbr" && "$qdisc" == "fq" ]]; then
        echo -e "  ${GREEN}${BOLD}● BBR 已完整启用且配置最优${NC}"
    elif [[ "$current" == "bbr" ]]; then
        echo -e "  ${YELLOW}${BOLD}● BBR 已启用，但队列规则建议改为 fq${NC}"
    else
        echo -e "  ${RED}${BOLD}● BBR 未启用${NC}"
    fi

    sep
}

#-------------------- 功能 2：启用 BBR --------------------
bbr_enable() {
    sep
    echo -e "${BOLD}          启用 BBR${NC}"
    sep
    echo ""

    local kernel_ver=$(get_kernel_version)
    local major=$(echo "$kernel_ver" | cut -d. -f1)
    local minor=$(echo "$kernel_ver" | cut -d. -f2)

    # 内核检查
    if [[ "$major" -lt 4 ]] || [[ "$major" -eq 4 && "$minor" -lt 9 ]]; then
        error "内核版本 $kernel_ver 低于 4.9，不支持 BBR。请先升级内核。"
    fi

    info "加载 tcp_bbr 模块..."
    modprobe tcp_bbr 2>/dev/null && ok "模块加载成功" || warn "模块加载返回非零（可能已编译进内核）"

    info "设置默认队列规则为 fq..."
    sysctl -w net.core.default_qdisc=fq >/dev/null
    ok "default_qdisc = fq"

    info "设置拥塞控制算法为 bbr..."
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
    ok "tcp_congestion_control = bbr"

    # 写入配置文件（持久化）
    info "写入持久化配置..."

    # 检测 sysctl 配置文件位置
    local sysctl_conf=""
    if [[ -d /etc/sysctl.d ]]; then
        sysctl_conf="/etc/sysctl.d/99-bbr.conf"
    else
        sysctl_conf="/etc/sysctl.conf"
    fi

    # 移除旧的 BBR 配置避免重复
    if grep -q "net.ipv4.tcp_congestion_control" "$sysctl_conf" 2>/dev/null; then
        sed -i '/net.ipv4.tcp_congestion_control/d' "$sysctl_conf"
    fi
    if grep -q "net.core.default_qdisc" "$sysctl_conf" 2>/dev/null; then
        sed -i '/net.core.default_qdisc/d' "$sysctl_conf"
    fi

    cat >> "$sysctl_conf" <<'EOF'

# BBR 拥塞控制算法配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    ok "配置已写入 ${sysctl_conf}"

    # 确保开机自动加载模块
    if [[ -f /etc/modules-load.d ]]; then
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
        ok "已配置开机自动加载模块"
    elif [[ -f /etc/modules ]]; then
        if ! grep -q "tcp_bbr" /etc/modules 2>/dev/null; then
            echo "tcp_bbr" >> /etc/modules
            ok "已添加 tcp_bbr 到 /etc/modules"
        fi
    fi

    echo ""
    info "应用 sysctl 配置..."
    sysctl -p "$sysctl_conf" >/dev/null 2>&1

    # 验证
    echo ""
    local current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [[ "$current" == "bbr" && "$qdisc" == "fq" ]]; then
        echo -e "  ${GREEN}${BOLD}● BBR 启用成功！配置已持久化。${NC}"
        echo ""
        echo -e "  ${BLUE}当前配置：${NC}"
        echo -e "    拥塞控制: ${GREEN}bbr${NC}"
        echo -e "    队列规则: ${GREEN}fq${NC}"
        echo -e "    配置文件: ${CYAN}${sysctl_conf}${NC}"
    else
        error "BBR 启用似乎未完全生效，请检查：sysctl -a | grep bbr"
    fi

    sep
}

#-------------------- 功能 3：禁用 BBR --------------------
bbr_disable() {
    sep
    echo -e "${BOLD}          禁用 BBR（恢复默认）${NC}"
    sep
    echo ""

    info "恢复默认拥塞控制算法为 cubic..."
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>/dev/null
    ok "tcp_congestion_control = cubic"

    info "恢复默认队列规则为 pfifo_fast..."
    sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null
    ok "default_qdisc = pfifo_fast"

    # 移除持久化配置
    info "清理持久化配置..."
    for conf in /etc/sysctl.d/99-bbr.conf /etc/sysctl.conf; do
        if [[ -f "$conf" ]]; then
            if grep -q "bbr" "$conf" 2>/dev/null; then
                sed -i '/bbr/d' "$conf"
                sed -i '/net.core.default_qdisc/d' "$conf"
                ok "已清理 ${conf}"
            fi
        fi
    done

    # 移除模块加载配置
    if [[ -f /etc/modules-load.d/bbr.conf ]]; then
        rm -f /etc/modules-load.d/bbr.conf
        ok "已移除模块自动加载配置"
    fi
    if [[ -f /etc/modules ]]; then
        sed -i '/^tcp_bbr$/d' /etc/modules 2>/dev/null
    fi

    echo ""
    echo -e "  ${YELLOW}${BOLD}● BBR 已禁用，恢复为默认 CUBIC 算法${NC}"
    sep
}

#-------------------- 功能 4：内核检测 & 升级建议 --------------------
kernel_check() {
    sep
    echo -e "${BOLD}          内核版本检测 & 升级建议${NC}"
    sep
    echo ""

    local kernel_ver=$(get_kernel_version)
    local major=$(echo "$kernel_ver" | cut -d. -f1)
    local minor=$(echo "$kernel_ver" | cut -d. -f2)

    echo -e "  ${BLUE}当前内核：${NC}${BOLD}${kernel_ver}${NC}"
    echo ""

    # BBR 版本支持矩阵
    echo -e "  ${BLUE}BBR 版本支持矩阵：${NC}"
    echo ""
    echo -e "    ${CYAN}内核版本${NC}      ${CYAN}BBRv1${NC}  ${CYAN}BBRv2${NC}  ${CYAN}BBRv3${NC}  ${CYAN}说明${NC}"
    echo -e "    ${CYAN}──────────────────────────────────────────────────────${NC}"
    echo -e "    < 4.9            ✗      ✗      ✗      不支持 BBR"
    echo -e "    4.9 ~ 5.x        ✓      ✗      ✗      仅 BBRv1（内核内置）"
    echo -e "    >= 5.13          ✓      ✓      ✗      BBRv2（需 Google 自定义内核）"
    echo -e "    >= 6.1           ✓      ✓      ✓      BBRv3（需 Google 自定义内核）"
    echo ""

    # 分析当前内核
    if [[ "$major" -lt 4 ]] || [[ "$major" -eq 4 && "$minor" -lt 9 ]]; then
        echo -e "  ${RED}${BOLD}● 当前内核不支持 BBR，需要升级内核${NC}"
        echo ""
        echo -e "  ${YELLOW}升级方案推荐：${NC}"
        echo ""

        # 检测发行版
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            local distro_id=${ID,,}
            case "$distro_id" in
                ubuntu)
                    echo -e "    ${CYAN}Ubuntu 方案：${NC}"
                    echo -e "      1) sudo apt install --install-recommends linux-generic-hwe-$(lsb_release -rs | cut -d. -f1)$(lsb_release -rs | cut -d. -f2)"
                    echo -e "      2) 或使用 Ubuntu HWE 内核：sudo apt install linux-hwe-$(lsb_release -cs)-$(lsb_release -rs)"
                    echo -e "      3) 或使用官方脚本升级：https://kernel.ubuntu.com/~kernel-ppa/mainline/"
                    ;;
                centos|rhel|rocky|almalinux)
                    echo -e "    ${CYAN}CentOS/RHEL/Rocky/AlmaLinux 方案：${NC}"
                    echo -e "      1) ELRepo（推荐）：https://elrepo.org/"
                    echo -e "         rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org"
                    echo -e "         yum install -y https://www.elrepo.org/elrepo-release-$(rpm -E '%rhel').el$(rpm -E '%centos_ver').noarch.rpm"
                    echo -e "         yum --enablerepo=elrepo-kernel install -y kernel-ml"
                    echo -e "      2) 或手动编译内核（见选项 5）"
                    ;;
                debian)
                    echo -e "    ${CYAN}Debian 方案：${NC}"
                    echo -e "      1) sudo apt install -t bookworm-backports linux-image-amd64"
                    echo -e "      2) 或使用官方脚本升级：https://kernel.ubuntu.com/~kernel-ppa/mainline/"
                    ;;
                fedora)
                    echo -e "    ${CYAN}Fedora 方案：${NC}"
                    echo -e "      1) sudo dnf update kernel"
                    echo -e "      2) Fedora 通常已包含最新内核"
                    ;;
                *)
                    echo -e "      建议使用发行版包管理器升级内核，或手动编译"
                    ;;
            esac
        fi
    elif [[ "$major" -eq 4 ]]; then
        echo -e "  ${YELLOW}${BOLD}● 当前内核仅支持 BBRv1${NC}"
        echo ""
        echo -e "  ${YELLOW}BBRv1 说明：${NC}"
        echo -e "    - Google 于 2016 年发布的初代 BBR 算法"
        echo -e "    - 相比 CUBIC 在高带宽高延迟网络上有显著提升"
        echo -e "    - 可能在多流竞争场景下占用过多带宽"
        echo ""
        echo -e "  ${YELLOW}升级建议：${NC}"
        echo -e "    - 升级到 5.13+ 可使用 BBRv2（需 Google 自定义内核）"
        echo -e "    - 升级到 6.1+ 可使用 BBRv3（需 Google 自定义内核）"
        echo -e "    - BBRv1 对大多数场景已足够，无需急于升级"
    elif [[ "$major" -ge 5 ]]; then
        echo -e "  ${GREEN}${BOLD}● 当前内核支持 BBRv1${NC}"
        if [[ "$major" -ge 5 && "$minor" -ge 13 ]]; then
            echo -e "  ${GREEN}● 内核 5.13+，可编译 Google 自定义内核获得 BBRv2${NC}"
        fi
        if [[ "$major" -ge 6 && "$minor" -ge 1 ]]; then
            echo -e "  ${GREEN}● 内核 6.1+，可编译 Google 自定义内核获得 BBRv3${NC}"
        fi
        echo ""
        echo -e "  ${CYAN}注意：${NC}BBRv2/v3 目前未合入主线内核，需要 Google 自定义内核"
        echo -e "    Google 内核项目：https://github.com/google/bbr"
    fi

    echo ""
    sep
}

#-------------------- 功能 5：编译安装最新内核 --------------------
kernel_compile() {
    sep
    echo -e "${BOLD}          编译安装最新内核（含 BBR）${NC}"
    sep
    echo ""

    warn "此过程需要较长时间（30~120 分钟），需要 2GB+ 内存和 20GB+ 磁盘空间"
    echo ""
    echo -n "确认继续？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "安装编译依赖..."

    # 检测发行版安装编译工具
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        local distro_id=${ID,,}
        case "$distro_id" in
            ubuntu|debian|linuxmint|pop)
                apt-get update
                apt-get install -y build-essential libncurses-dev bison flex libssl-dev libelf-dev \
                    bc dwarves rsync wget cpio fakeroot initramfs-tools
                ;;
            centos|rhel|rocky|almalinux|ol|fedora)
                local pm="yum"
                command -v dnf &>/dev/null && pm="dnf"
                $pm groupinstall -y "Development Tools"
                $pm install -y ncurses-devel bison flex openssl-devel elfutils-libelf-devel \
                    bc dwarves rsync wget cpio rpm-build
                ;;
            *)
                error "不支持的发行版，请手动安装编译工具后编译内核"
                ;;
        esac
    fi

    echo ""
    info "选择内核来源："
    echo -e "  ${CYAN}1)${NC} 稳定版内核（kernel.org，含 BBRv1）"
    echo -e "  ${CYAN}2)${NC} Google BBR 内核（含 BBRv2/v3，实验性）"
    echo ""
    echo -n "请选择 [1/2]（默认 1）: "
    read -r kernel_choice

    local kernel_url=""
    local kernel_dir=""

    if [[ "$kernel_choice" == "2" ]]; then
        info "获取 Google BBR 内核..."
        kernel_url="https://github.com/google/bbr.git"
        kernel_dir="google-bbr"
    else
        # 获取最新稳定版内核
        info "查询最新稳定版内核..."
        local latest_version
        latest_version=$(curl -fsSL "https://www.kernel.org/feeds/kdist.xml" 2>/dev/null | \
            grep -oP '(?<=<title>Linux )\d+\.\d+\.\d+' | head -3 | tail -1)
        if [[ -z "$latest_version" ]]; then
            latest_version="6.12"  # fallback
            warn "无法自动获取最新版本，使用 ${latest_version}"
        fi
        info "最新稳定版内核：${latest_version}"
        kernel_url="https://cdn.kernel.org/pub/linux/kernel/v$(echo "$latest_version" | cut -d. -f1).x/linux-${latest_version}.tar.xz"
        kernel_dir="linux-${latest_version}"
    fi

    echo ""
    info "下载内核源码（过程可能较慢）..."

    cd /usr/src

    if [[ "$kernel_choice" == "2" ]]; then
        if [[ -d "$kernel_dir" ]]; then
            warn "目录 $kernel_dir 已存在，更新中..."
            cd "$kernel_dir" && git pull
        else
            git clone --depth=1 "$kernel_url" "$kernel_dir"
            cd "$kernel_dir"
        fi
    else
        if [[ -d "$kernel_dir" ]]; then
            warn "目录 $kernel_dir 已存在，跳过下载"
        else
            wget -q --show-progress "$kernel_url" -O /tmp/kernel.tar.xz
            tar -xf /tmp/kernel.tar.xz -C /usr/src/
            rm -f /tmp/kernel.tar.xz
        fi
        cd "/usr/src/$kernel_dir"
    fi

    echo ""
    info "配置内核..."

    # 使用当前内核配置作为基础
    if [[ -f "/boot/config-$(uname -r)" ]]; then
        cp "/boot/config-$(uname -r)" .config
        yes "" | make oldconfig
    else
        make defconfig
    fi

    # 确保 BBR 相关选项启用
    scripts/config --enable CONFIG_TCP_CONG_BBR
    scripts/config --enable CONFIG_NET_SCH_FQ
    info "已启用 CONFIG_TCP_CONG_BBR 和 CONFIG_NET_SCH_FQ"

    echo ""
    info "开始编译内核..."
    warn "此过程需要较长时间，请耐心等待"

    # 使用所有 CPU 核心并行编译
    local cores=$(nproc)
    make -j"$cores" bzImage modules 2>&1 | tail -20

    echo ""
    info "安装内核模块..."
    make modules_install

    echo ""
    info "安装内核..."
    make install

    echo ""
    info "更新引导加载器..."
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -c -k "$(make kernelrelease)"
    elif command -v dracut &>/dev/null; then
        dracut --force "/boot/initramfs-$(make kernelrelease).img" "$(make kernelrelease)"
    fi

    if command -v update-grub &>/dev/null; then
        update-grub
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}● 内核编译安装完成！${NC}"
    echo ""
    warn "请重启系统以使用新内核：sudo reboot"
    warn "重启后运行此脚本选择「启用 BBR」完成配置"
    sep
}

#-------------------- 功能 6：BBR 参数调优 --------------------
bbr_tuning() {
    sep
    echo -e "${BOLD}          BBR 参数调优${NC}"
    sep
    echo ""

    local current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$current" != "bbr" ]]; then
        warn "BBR 当前未启用，建议先启用 BBR 再调优"
        echo ""
        echo -n "仍要继续调优配置？(y/N): "
        read -r force
        if [[ ! "$force" =~ ^[Yy]$ ]]; then
            info "已取消"
            return
        fi
    fi

    echo -e "  ${BOLD}请选择优化场景：${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} VPS / 云服务器（推荐，通用优化）"
    echo -e "  ${CYAN}2)${NC} 高带宽长肥管道（国际线路、大文件传输）"
    echo -e "  ${CYAN}3)${NC} 低延迟 / 游戏加速（优先低延迟）"
    echo -e "  ${CYAN}4)${NC} 恢复默认参数"
    echo ""
    echo -n "请选择 [1/2/3/4]（默认 1）: "
    read -r tune_choice

    local sysctl_conf=""
    if [[ -d /etc/sysctl.d ]]; then
        sysctl_conf="/etc/sysctl.d/99-bbr-tuning.conf"
    else
        sysctl_conf="/etc/sysctl.conf"
    fi

    # 清理旧的调优配置
    if [[ -f "$sysctl_conf" ]]; then
        rm -f "$sysctl_conf"
    fi

    case "$tune_choice" in
        2)
            # 高带宽长肥管道
            info "应用高带宽长肥管道优化..."
            cat > "$sysctl_conf" <<'EOF'
# BBR 高带宽长肥管道优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 增大缓冲区
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.rmem_max = 16777216
net.ipv4.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216

# 增大连接队列
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000

# TCP 优化
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# 保持长连接
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# TCP 缓冲区自动调节
net.ipv4.tcp_mtu_probing = 1
EOF
            ;;
        3)
            # 低延迟
            info "应用低延迟优化..."
            cat > "$sysctl_conf" <<'EOF'
# BBR 低延迟优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 减小缓冲区以降低延迟
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.ipv4.rmem_max = 4194304
net.ipv4.wmem_max = 4194304
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 131072 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304

# 启用 MTU 探测
net.ipv4.tcp_mtu_probing = 1

# 减少 TIME_WAIT
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# TCP Fast Open
net.ipv4.tcp_fastopen = 3

# 低延迟队列
net.core.netdev_max_backlog = 2000
EOF
            ;;
        4)
            # 恢复默认
            info "恢复默认 TCP 参数..."
            # 移除 BBR 调优配置
            if [[ "$sysctl_conf" != "/etc/sysctl.conf" && -f "$sysctl_conf" ]]; then
                rm -f "$sysctl_conf"
            fi
            echo -e "  ${GREEN}● 已恢复默认参数${NC}"
            return
            ;;
        *)
            # VPS / 云服务器通用优化（默认）
            info "应用 VPS/云服务器通用优化..."
            cat > "$sysctl_conf" <<'EOF'
# BBR VPS/云服务器通用优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 优化缓冲区
net.core.rmem_max = 12582912
net.core.wmem_max = 12582912
net.ipv4.rmem_max = 12582912
net.ipv4.wmem_max = 12582912
net.core.rmem_default = 524288
net.core.wmem_default = 524288
net.ipv4.tcp_rmem = 4096 524288 12582912
net.ipv4.tcp_wmem = 4096 262144 12582912

# 优化连接
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192

# TCP 基础优化
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_keepalive_time = 600

# 减少 TIME_WAIT
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# TCP Fast Open（客户端+服务端）
net.ipv4.tcp_fastopen = 3

# 本地端口范围
net.ipv4.ip_local_port_range = 1024 65535
EOF
            ;;
    esac

    # 应用配置
    sysctl -p "$sysctl_conf" >/dev/null 2>&1

    echo ""
    echo -e "  ${GREEN}${BOLD}● 参数调优完成！配置文件：${NC}${CYAN}${sysctl_conf}${NC}"
    sep
}

#-------------------- 功能 7：网络性能测试 --------------------
bbr_test() {
    sep
    echo -e "${BOLD}          网络性能测试${NC}"
    sep
    echo ""

    # 检查是否安装了必要工具
    local has_iperf=false
    local has_wget=true
    command -v iperf3 &>/dev/null && has_iperf=true
    command -v wget &>/dev/null || has_wget=false
    command -v curl &>/dev/null || has_wget=false

    echo -e "  ${BOLD}选择测试方式：${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} TCP 吞吐量测试（需要 iperf3 服务端）"
    echo -e "  ${CYAN}2)${NC} 下载速度测试（从公共服务器下载文件）"
    echo -e "  ${CYAN}3)${NC} 仅查看当前 TCP 连接使用的拥塞控制算法"
    echo ""
    echo -n "请选择 [1/2/3]（默认 3）: "
    read -r test_choice

    case "$test_choice" in
        1)
            if [[ "$has_iperf" != "true" ]]; then
                warn "未安装 iperf3，正在安装..."
                if [[ -f /etc/os-release ]]; then
                    . /etc/os-release
                    case "${ID,,}" in
                        ubuntu|debian|linuxmint|pop)
                            apt-get install -y iperf3
                            ;;
                        centos|rhel|rocky|almalinux|ol|fedora)
                            command -v dnf &>/dev/null && dnf install -y iperf3 || yum install -y iperf3
                            ;;
                    esac
                fi
            fi

            echo ""
            echo -n "输入 iperf3 服务端地址（或 Ctrl+C 取消）: "
            read -r server
            if [[ -z "$server" ]]; then
                warn "未输入地址，测试取消"
                return
            fi

            echo ""
            info "开始 TCP 吞吐量测试..."
            echo -e "  当前拥塞控制算法: ${CYAN}$(sysctl -n net.ipv4.tcp_congestion_control)${NC}"
            echo ""
            iperf3 -c "$server" -t 10 -R --connect-timeout 5000 || warn "连接失败，请确认服务端可用"
            ;;
        2)
            if [[ "$has_wget" != "true" ]]; then
                error "未安装 wget 或 curl，无法进行下载测试"
            fi

            echo ""
            info "选择下载测试服务器："
            echo -e "  ${CYAN}1)${NC} Cloudflare（全球节点）"
            echo -e "  ${CYAN}2)${NC} Linode（美西节点）"
            echo -e "  ${CYAN}3)${NC} 自定义 URL"
            echo ""
            echo -n "请选择 [1/2/3]（默认 1）: "
            read -r dl_choice

            local test_url=""
            case "$dl_choice" in
                2) test_url="http://speedtest.dallas.linode.com/100MB-dallas.bin" ;;
                3)
                    echo -n "输入下载 URL: "
                    read -r test_url
                    ;;
                *) test_url="https://speed.cloudflare.com/__down?bytes=100000000" ;;
            esac

            echo ""
            info "开始下载速度测试..."
            echo -e "  当前拥塞控制算法: ${CYAN}$(sysctl -n net.ipv4.tcp_congestion_control)${NC}"
            echo ""
            if command -v wget &>/dev/null; then
                wget -O /dev/null "$test_url" 2>&1 | tail -5
            else
                curl -o /dev/null -w "  下载速度: %{speed_download} bytes/sec\n" "$test_url"
            fi
            ;;
        *)
            # 查看当前 TCP 连接的拥塞控制算法
            echo -e "  ${BLUE}当前系统默认算法：${NC}${CYAN}$(sysctl -n net.ipv4.tcp_congestion_control)${NC}"
            echo ""

            echo -e "  ${BLUE}活跃 TCP 连接使用的算法统计：${NC}"
            echo ""

            # 统计 /proc/net/tcp 中连接使用的算法
            local ss_output
            if command -v ss &>/dev/null; then
                ss -ti 2>/dev/null | grep -i "cubic\|bbr\|reno" | sort | uniq -c | sort -rn | while read -r count algo; do
                    echo -e "    ${CYAN}$(echo "$algo" | grep -oP '(?<=cubic:|bbr:|reno:)\S+')${NC}: ${count} 个连接"
                done
            fi

            # 更简单的方式：通过 ss 查看各连接
            echo ""
            echo -e "  ${BLUE}示例连接详情（ss -ti）：${NC}"
            local conn_count=0
            ss -ti state established '( dport = :443 or sport = :443 )' 2>/dev/null | head -20 | while IFS= read -r line; do
                if [[ $conn_count -lt 20 ]]; then
                    echo -e "    ${CYAN}${line}${NC}"
                    conn_count=$((conn_count + 1))
                fi
            done

            # 如果 ss 没有详细输出
            if ! ss -ti 2>/dev/null | grep -q "cubic\|bbr"; then
                echo -e "    ${YELLOW}(当前无活跃连接或 ss 不支持详细算法显示)${NC}"
                echo ""
                echo -e "    ${CYAN}提示：${NC}可以访问一个网站后再次查看"
            fi
            ;;
    esac

    echo ""
    sep
}

#-------------------- 主循环 --------------------
main() {
    needs_root

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1) bbr_status ;;
            2) bbr_enable ;;
            3) bbr_disable ;;
            4) kernel_check ;;
            5) kernel_compile ;;
            6) bbr_tuning ;;
            7) bbr_test ;;
            0|q|Q)
                echo ""
                info "退出 BBR 管理脚本"
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
