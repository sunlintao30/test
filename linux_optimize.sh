#!/bin/bash
#=============================================================================
# Linux 系统优化脚本
# 功能：内核参数调优 / 网络优化 / 内存管理 / 文件描述符 / 交换分区 / DNS / 磁盘调度
# 支持：Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora / OpenWrt
# 用法：chmod +x linux_optimize.sh && sudo ./linux_optimize.sh
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
info()  { echo -e "${GREEN}[信息]${NC} $*"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
error() { echo -e "${RED}[错误]${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
fail()  { echo -e "${RED}  ✗${NC} $*"; }
sep()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
sep_s() { echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本：sudo $0"
        exit 1
    fi
}

#-------------------- 全局变量 --------------------
BACKUP_DIR="/opt/sys_optimize_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_D_DIR="/etc/sysctl.d"
LIMITS_CONF="/etc/security/limits.conf"
LIMITS_D_DIR="/etc/security/limits.d"

#-------------------- 获取系统信息 --------------------
get_system_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_NAME="${PRETTY_NAME}"
        OS_VERSION="${VERSION_ID}"
    else
        OS_NAME="未知系统"
        OS_ID="unknown"
    fi

    OS_ARCH=$(uname -m)
    OS_KERNEL=$(uname -r)
    OS_MEM=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
    OS_CPU=$(nproc 2>/dev/null || echo "未知")
    OS_UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "未知")
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    get_system_info

    sep
    echo -e "${BOLD}             Linux 系统优化脚本${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}系统：${NC}${OS_NAME}"
    echo -e "  ${BLUE}内核：${NC}${OS_KERNEL}  |  ${BLUE}架构：${NC}${OS_ARCH}  |  ${BLUE}CPU：${NC}${OS_CPU}核  |  ${BLUE}内存：${NC}${OS_MEM}MB"
    echo -e "  ${BLUE}运行：${NC}${OS_UPTIME}"
    echo ""

    # 显示当前优化状态
    echo -e "  ${BOLD}当前优化状态：${NC}"
    echo -n "  BBR: "
    if lsmod 2>/dev/null | grep -q "tcp_bbr"; then
        echo -e "${GREEN}已启用${NC}"
    else
        echo -e "${YELLOW}未启用${NC}"
    fi
    echo -n "  Swappiness: "
    echo -e "${CYAN}$(cat /proc/sys/vm/swappiness 2>/dev/null || echo '未知')${NC}"
    echo -n "  File Max:  "
    echo -e "${CYAN}$(cat /proc/sys/fs/file-max 2>/dev/null || echo '未知')${NC}"
    echo ""

    sep
    echo ""

    echo -e "  ${CYAN}【一键优化】${NC}"
    echo -e "  ${CYAN} 1)${NC} 一键全面优化（推荐，自动检测最佳配置）"
    echo -e "  ${CYAN} 2)${NC} 使用预设场景优化"
    echo ""

    echo -e "  ${CYAN}【分类优化】${NC}"
    echo -e "  ${CYAN} 3)${NC} 内核参数优化（sysctl.conf）"
    echo -e "  ${CYAN} 4)${NC} 网络与 TCP 优化"
    echo -e "  ${CYAN} 5)${NC} 内存与交换分区优化"
    echo -e "  ${CYAN} 6)${NC} 文件描述符与系统限制优化"
    echo -e "  ${CYAN} 7)${NC} DNS 优化"
    echo -e "  ${CYAN} 8)${NC} 磁盘 I/O 调度优化"
    echo ""

    echo -e "  ${CYAN}【辅助】${NC}"
    echo -e "  ${CYAN} 9)${NC} 查看当前系统参数"
    echo -e "  ${CYAN}10)${NC} 系统性能测试"
    echo -e "  ${CYAN}11)${NC} 备份当前配置"
    echo -e "  ${CYAN}12)${NC} 恢复优化前配置"
    echo -e "  ${CYAN}13)${NC} 恢复系统默认值"
    echo -e "  ${CYAN} 0)${NC} 退出"
    echo ""

    sep
    echo -n "请输入选项: "
}

#-------------------- 备份当前配置 --------------------
backup_config() {
    info "备份当前系统配置..."
    mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"

    [[ -f "$SYSCTL_CONF" ]] && cp "$SYSCTL_CONF" "${BACKUP_DIR}/${TIMESTAMP}/sysctl.conf"
    [[ -d "$SYSCTL_D_DIR" ]] && cp -r "$SYSCTL_D_DIR" "${BACKUP_DIR}/${TIMESTAMP}/sysctl.d" 2>/dev/null
    [[ -f "$LIMITS_CONF" ]] && cp "$LIMITS_CONF" "${BACKUP_DIR}/${TIMESTAMP}/limits.conf"
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "${BACKUP_DIR}/${TIMESTAMP}/resolv.conf"
    [[ -f /etc/fstab ]] && cp /etc/fstab "${BACKUP_DIR}/${TIMESTAMP}/fstab"
    [[ -f /etc/grub ]] && cp /etc/grub "${BACKUP_DIR}/${TIMESTAMP}/grub" 2>/dev/null
    [[ -f /etc/default/grub ]] && cp /etc/default/grub "${BACKUP_DIR}/${TIMESTAMP}/grub_default" 2>/dev/null

    # 记录当前参数值
    cat > "${BACKUP_DIR}/${TIMESTAMP}/current_params.txt" <<EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
系统: ${OS_NAME}
内核: ${OS_KERNEL}
swappiness: $(cat /proc/sys/vm/swappiness)
file-max: $(cat /proc/sys/fs/file-max)
tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
somaxconn: $(sysctl -n net.core.somaxconn 2>/dev/null)
rmem_max: $(sysctl -n net.core.rmem_max 2>/dev/null)
wmem_max: $(sysctl -n net.core.wmem_max 2>/dev/null)
nofile_limit: $(ulimit -n)
EOF

    ok "配置已备份到 ${BACKUP_DIR}/${TIMESTAMP}"
}

#-------------------- 功能 1：一键全面优化 --------------------
auto_optimize() {
    sep
    echo -e "${BOLD}              一键全面优化${NC}"
    sep
    echo ""

    echo -e "  ${YELLOW}此操作将自动优化系统内核参数、网络、内存、文件描述符等${NC}"
    echo -e "  ${YELLOW}优化前会自动备份当前配置，可随时恢复${NC}"
    echo ""

    echo -n "  确认执行一键优化？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    echo -e "${BOLD}开始全面优化...${NC}"
    echo ""

    # 备份
    backup_config

    # 执行各项优化
    optimize_sysctl
    optimize_network
    optimize_memory
    optimize_limits
    optimize_dns

    echo ""
    echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}${BOLD}              ● 全面优化完成！${NC}"
    echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${YELLOW}建议重启系统使所有优化生效${NC}"
    echo -e "  ${YELLOW}备份位置：${BACKUP_DIR}/${TIMESTAMP}${NC}"

    echo ""
    echo -n "  是否立即重启？(y/N): "
    read -r reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
        info "系统将在 5 秒后重启..."
        sleep 5
        reboot
    fi

    sep
}

#-------------------- 功能 2：预设场景优化 --------------------
preset_optimize() {
    sep
    echo -e "${BOLD}              预设场景优化${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}请选择使用场景：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} Web 服务器  ${GREEN}（Nginx/Apache/Caddy）${NC}"
    echo -e "      优化：高并发连接、TIME_WAIT 复用、小文件传输"
    echo ""
    echo -e "  ${CYAN} 2)${NC} 数据库服务器 ${GREEN}（MySQL/PostgreSQL/Redis）${NC}"
    echo -e "      优化：大内存页、I/O 调度、减少交换、提高缓存"
    echo ""
    echo -e "  ${CYAN} 3)${NC} 代理/网关    ${GREEN}（frp/nginx-stream/Haproxy）${NC}"
    echo -e "      优化：超大连接数、端口复用、缓冲区调优"
    echo ""
    echo -e "  ${CYAN} 4)${NC} 通用服务器   ${GREEN}（均衡优化）${NC}"
    echo -e "      优化：各方面均衡，适合大多数场景"
    echo ""

    echo -n "请选择 [1-4]（默认 4）: "
    read -r preset_choice

    echo ""
    echo -n "  确认执行优化？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    backup_config

    case "$preset_choice" in
        1) preset_web ;;
        2) preset_database ;;
        3) preset_proxy ;;
        *) preset_general ;;
    esac

    echo ""
    echo -e "  ${GREEN}${BOLD}● 场景优化完成！${NC}"
    echo ""
    echo -n "  是否立即重启？(y/N): "
    read -r reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
        reboot
    fi

    sep
}

# Web 服务器预设
preset_web() {
    info "应用 Web 服务器优化方案..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== Web 服务器优化 =====
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 200000
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mem = 262144 524288 786432
EOF

    sysctl -p 2>/dev/null

    optimize_limits 65535
    info "Web 服务器优化已应用"
}

# 数据库服务器预设
preset_database() {
    info "应用数据库服务器优化方案..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== 数据库服务器优化 =====
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.vfs_cache_pressure = 50
vm.zone_reclaim_mode = 0
vm.min_free_kbytes = 65536
kernel.sched_autogroup_enabled = 0
kernel.sched_migration_cost_ns = 5000000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
EOF

    sysctl -p 2>/dev/null

    optimize_limits 65535

    # 关闭透明大页（数据库建议）
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
        echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null
        ok "透明大页已关闭（THP）"
    fi

    info "数据库服务器优化已应用"
}

# 代理/网关服务器预设
preset_proxy() {
    info "应用代理/网关优化方案..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== 代理/网关优化 =====
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 100000
net.ipv4.tcp_max_syn_backlog = 100000
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 500000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries2 = 8
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_mem = 262144 1048576 2097152
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl -p 2>/dev/null

    optimize_limits 1048576

    # 启用 BBR
    enable_bbr

    info "代理/网关优化已应用"
}

# 通用服务器预设
preset_general() {
    info "应用通用服务器优化方案..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== 通用服务器优化 =====
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 200000
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

    sysctl -p 2>/dev/null

    optimize_limits 65535
    enable_bbr

    info "通用服务器优化已应用"
}

#-------------------- 功能 3：内核参数优化 --------------------
optimize_sysctl() {
    sep_s
    echo -e "${BOLD}  内核参数优化${NC}"
    sep_s
    echo ""

    info "应用内核参数优化..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== Linux 内核参数优化（自动生成）=====

# --- 文件系统 ---
fs.file-max = 655350
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
fs.aio-max-nr = 1048576

# --- 内核 ---
kernel.pid_max = 65536
kernel.threads-max = 65536
kernel.core_uses_pid = 1
kernel.msgmax = 65536
kernel.msgmnb = 65536
kernel.sem = 250 32000 100 128
kernel.shmall = 4294967296
kernel.shmmax = 68719476736
kernel.sysrq = 0
kernel.randomize_va_space = 2
EOF

    sysctl -p 2>/dev/null
    ok "内核参数优化完成"
}

#-------------------- 功能 4：网络与 TCP 优化 --------------------
optimize_network() {
    sep_s
    echo -e "${BOLD}  网络与 TCP 优化${NC}"
    sep_s
    echo ""

    info "应用网络参数优化..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== 网络与 TCP 优化 =====

# --- 连接队列与并发 ---
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1

# --- TIME_WAIT 优化 ---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 200000
net.ipv4.tcp_max_orphans = 65536

# --- Keepalive ---
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30

# --- 端口范围 ---
net.ipv4.ip_local_port_range = 1024 65535

# --- 缓冲区 ---
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mem = 262144 524288 786432

# --- TCP 高级特性 ---
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1

# --- UDP 优化 ---
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# --- IPv6 ---
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1

# --- 路由与转发 ---
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# --- 安全 ---
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

    sysctl -p 2>/dev/null

    # 启用 BBR
    enable_bbr

    ok "网络与 TCP 优化完成"
}

#-------------------- 启用 BBR --------------------
enable_bbr() {
    local kernel_ver=$(uname -r | cut -d. -f1,2)
    local required="4.9"

    if [[ "$(printf '%s\n' "$required" "$kernel_ver" | sort -V | head -1)" != "$required" ]]; then
        warn "内核版本 ${kernel_ver} 低于 4.9，不支持 BBR"
        return
    fi

    if lsmod 2>/dev/null | grep -q "tcp_bbr"; then
        ok "BBR 已启用"
        return
    fi

    info "启用 BBR 拥塞控制算法..."

    modprobe tcp_bbr 2>/dev/null || true

    if ! grep -q "tcp_bbr" "$SYSCTL_CONF" 2>/dev/null; then
        cat >> "$SYSCTL_CONF" <<'EOF'

# ===== BBR 拥塞控制 =====
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    fi

    sysctl -w net.core.default_qdisc=fq 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null

    if lsmod 2>/dev/null | grep -q "tcp_bbr"; then
        ok "BBR 已成功启用"
    else
        warn "BBR 启用失败，可能需要更新内核"
    fi
}

#-------------------- 功能 5：内存与交换分区优化 --------------------
optimize_memory() {
    sep_s
    echo -e "${BOLD}  内存与交换分区优化${NC}"
    sep_s
    echo ""

    info "应用内存管理优化..."

    cat >> "$SYSCTL_CONF" <<'EOF'

# ===== 内存管理优化 =====
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.min_free_kbytes = 65536
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
vm.zone_reclaim_mode = 0
vm.max_map_count = 262144
EOF

    sysctl -p 2>/dev/null

    ok "已设置 swappiness = 10（减少 swap 使用）"
    ok "内存管理优化完成"
}

#-------------------- 功能 6：文件描述符与系统限制优化 --------------------
optimize_limits() {
    local nofile_limit="${1:-65535}"

    sep_s
    echo -e "${BOLD}  文件描述符与系统限制优化${NC}"
    sep_s
    echo ""

    info "设置文件描述符限制为 ${nofile_limit}..."

    # 修改 limits.conf
    if ! grep -q "^* soft nofile" "$LIMITS_CONF" 2>/dev/null; then
        cat >> "$LIMITS_CONF" <<EOF

# ===== 系统优化：文件描述符限制 =====
* soft nofile ${nofile_limit}
* hard nofile ${nofile_limit}
root soft nofile ${nofile_limit}
root hard nofile ${nofile_limit}
* soft nproc ${nofile_limit}
* hard nproc ${nofile_limit}
root soft nproc unlimited
root hard nproc unlimited
EOF
    else
        sed -i "s/^* soft nofile.*/* soft nofile ${nofile_limit}/" "$LIMITS_CONF"
        sed -i "s/^* hard nofile.*/* hard nofile ${nofile_limit}/" "$LIMITS_CONF"
        sed -i "s/^root soft nofile.*/root soft nofile ${nofile_limit}/" "$LIMITS_CONF"
        sed -i "s/^root hard nofile.*/root hard nofile ${nofile_limit}/" "$LIMITS_CONF"
    fi

    # 创建 limits.d 配置
    mkdir -p "$LIMITS_D_DIR"
    cat > "${LIMITS_D_DIR}/90-nofile.conf" <<EOF
# 系统优化：文件描述符限制
* soft nofile ${nofile_limit}
* hard nofile ${nofile_limit}
root soft nofile ${nofile_limit}
root hard nofile ${nofile_limit}
EOF

    # 设置 systemd limits
    if [[ -d /etc/systemd/system.conf.d ]]; then
        mkdir -p /etc/systemd/system.conf.d
        cat > /etc/systemd/system.conf.d/limits.conf <<EOF
[Manager]
DefaultLimitNOFILE=${nofile_limit}
DefaultLimitNPROC=${nofile_limit}
DefaultTasksMax=${nofile_limit}
EOF
    fi

    # 立即生效
    ulimit -n "$nofile_limit" 2>/dev/null || true
    sysctl -w fs.file-max=655350 2>/dev/null || true

    ok "文件描述符限制已设置为 ${nofile_limit}"
}

#-------------------- 功能 7：DNS 优化 --------------------
optimize_dns() {
    sep_s
    echo -e "${BOLD}  DNS 优化${NC}"
    sep_s
    echo ""

    echo -e "  ${BOLD}选择 DNS 服务器：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 国内推荐（阿里 + 腾讯 + 114）"
    echo -e "  ${CYAN} 2)${NC} 国际推荐（Google + Cloudflare）"
    echo -e "  ${CYAN} 3)${NC} 自定义 DNS"
    echo -e "  ${CYAN} 4)${NC} 仅查看当前 DNS 配置"
    echo ""

    echo -n "请选择 [1-4]（默认 1）: "
    read -r dns_choice

    case "$dns_choice" in
        2)
            info "配置国际 DNS（Google + Cloudflare）..."
            cat > /etc/resolv.conf <<'EOF'
# 国际 DNS 优化
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
            ;;
        3)
            echo -n "  输入主 DNS: "
            read -r dns1
            echo -n "  输入备 DNS: "
            read -r dns2
            echo -n "  输入第三 DNS（可选）: "
            read -r dns3
            cat > /etc/resolv.conf <<EOF
# 自定义 DNS
nameserver ${dns1}
nameserver ${dns2}
EOF
            [[ -n "$dns3" ]] && echo "nameserver ${dns3}" >> /etc/resolv.conf
            ;;
        4)
            # 仅查看
            ;;
        *)
            info "配置国内 DNS（阿里 + 腾讯 + 114）..."
            cat > /etc/resolv.conf <<'EOF'
# 国内 DNS 优化
nameserver 223.5.5.5
nameserver 223.6.6.6
nameserver 119.29.29.29
nameserver 114.114.114.114
EOF
            ;;
    esac

    # 保护 resolv.conf 不被覆盖
    if [[ ! "$dns_choice" == "4" ]]; then
        chattr +i /etc/resolv.conf 2>/dev/null && ok "已锁定 /etc/resolv.conf" || warn "无法锁定 /etc/resolv.conf（可能需要 chattr）"
    fi

    echo ""
    echo -e "  ${BOLD}当前 DNS 配置：${NC}"
    grep "^nameserver" /etc/resolv.conf 2>/dev/null | while read -r line; do
        echo -e "    ${CYAN}${line}${NC}"
    done

    echo ""
    echo -e "  ${YELLOW}提示：部分云服务器/VPS 可能通过 DHCP 自动覆盖 DNS，可安装 resolvconf 管理${NC}"

    ok "DNS 优化完成"
}

#-------------------- 功能 8：磁盘 I/O 调度优化 --------------------
optimize_io() {
    sep_s
    echo -e "${BOLD}  磁盘 I/O 调度优化${NC}"
    sep_s
    echo ""

    info "检测磁盘设备..."

    local disks=$(lsblk -d -o NAME,TYPE,ROTA 2>/dev/null | grep "disk" | awk '{print $1, $2, $3}')

    echo ""
    echo -e "  ${BOLD}磁盘列表：${NC}"
    echo ""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local dev_name=$(echo "$line" | awk '{print $1}')
        local is_rotational=$(echo "$line" | awk '{print $3}')
        local dev_type="固态硬盘"
        local scheduler=""

        if [[ "$is_rotational" == "1" ]]; then
            dev_type="机械硬盘"
        fi

        scheduler=$(cat "/sys/block/${dev_name}/queue/scheduler" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' || echo "未知")

        echo -e "  ${CYAN}/dev/${dev_name}${NC}  ${BLUE}${dev_type}${NC}  当前调度器: ${GREEN}${scheduler}${NC}"
    done <<< "$disks"

    echo ""

    echo -e "  ${BOLD}调度器说明：${NC}"
    echo -e "  ${CYAN}mq-deadline${NC}  - 通用推荐，适合 SSD 和 HDD"
    echo -e "  ${CYAN}none / noop  ${NC}  - 适合 SSD/NVMe，减少 CPU 开销"
    echo -e "  ${CYAN}bfq          ${NC}  - 适合机械硬盘，公平调度"
    echo -e "  ${CYAN}kyber        ${NC}  - 适合 NVMe SSD，低延迟"
    echo ""

    echo -e "  ${YELLOW}建议：SSD 使用 none，HDD 使用 mq-deadline 或 bfq${NC}"
    echo ""
    echo -n "  是否自动优化磁盘调度器？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local dev_name=$(echo "$line" | awk '{print $1}')
        local is_rotational=$(echo "$line" | awk '{print $3}')

        local target_scheduler="none"
        if [[ "$is_rotational" == "1" ]]; then
            target_scheduler="mq-deadline"
        fi

        if echo "$target_scheduler" > "/sys/block/${dev_name}/queue/scheduler" 2>/dev/null; then
            ok "/dev/${dev_name} 调度器 -> ${target_scheduler}"
        else
            warn "/dev/${dev_name} 调度器切换失败，跳过"
        fi
    done <<< "$disks"

    ok "磁盘 I/O 调度优化完成"
}

#-------------------- 功能 9：查看当前系统参数 --------------------
show_current_params() {
    sep
    echo -e "${BOLD}              当前系统参数${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}--- 内核参数 ---${NC}"
    echo -e "  ${CYAN}swappiness:${NC}         $(cat /proc/sys/vm/swappiness)"
    echo -e "  ${CYAN}vfs_cache_pressure:${NC} $(cat /proc/sys/vm/vfs_cache_pressure)"
    echo -e "  ${CYAN}dirty_ratio:${NC}        $(cat /proc/sys/vm/dirty_ratio)"
    echo -e "  ${CYAN}dirty_background_ratio:${NC} $(cat /proc/sys/vm/dirty_background_ratio)"
    echo -e "  ${CYAN}overcommit_memory:${NC}  $(cat /proc/sys/vm/overcommit_memory)"
    echo ""

    echo -e "  ${BOLD}--- 文件系统 ---${NC}"
    echo -e "  ${CYAN}file-max:${NC}           $(cat /proc/sys/fs/file-max)"
    echo -e "  ${CYAN}file-nr:${NC}            $(cat /proc/sys/fs/file-nr)"
    echo -e "  ${CYAN}inotify max_user_watches:${NC} $(cat /proc/sys/fs/inotify/max_user_watches)"
    echo ""

    echo -e "  ${BOLD}--- 网络 ---${NC}"
    echo -e "  ${CYAN}tcp_congestion_control:${NC} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    echo -e "  ${CYAN}somaxconn:${NC}          $(sysctl -n net.core.somaxconn 2>/dev/null)"
    echo -e "  ${CYAN}netdev_max_backlog:${NC} $(sysctl -n net.core.netdev_max_backlog 2>/dev/null)"
    echo -e "  ${CYAN}tcp_max_syn_backlog:${NC} $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null)"
    echo -e "  ${CYAN}tcp_tw_reuse:${NC}       $(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)"
    echo -e "  ${CYAN}tcp_fin_timeout:${NC}    $(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null)"
    echo -e "  ${CYAN}tcp_fastopen:${NC}       $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)"
    echo -e "  ${CYAN}rmem_max:${NC}           $(sysctl -n net.core.rmem_max 2>/dev/null)"
    echo -e "  ${CYAN}wmem_max:${NC}           $(sysctl -n net.core.wmem_max 2>/dev/null)"
    echo -e "  ${CYAN}ip_local_port_range:${NC} $(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null)"
    echo ""

    echo -e "  ${BOLD}--- 系统限制 ---${NC}"
    echo -e "  ${CYAN}ulimit -n:${NC}          $(ulimit -n)"
    echo -e "  ${CYAN}ulimit -u:${NC}          $(ulimit -u)"
    echo ""

    echo -e "  ${BOLD}--- 磁盘 I/O ---${NC}"
    for disk in $(lsblk -d -o NAME 2>/dev/null | grep -v NAME); do
        local sched=$(cat "/sys/block/${disk}/queue/scheduler" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' || echo "未知")
        echo -e "  ${CYAN}/dev/${disk}:${NC} ${sched}"
    done

    echo ""
    echo -e "  ${BOLD}--- BBR 状态 ---${NC}"
    if lsmod 2>/dev/null | grep -q "tcp_bbr"; then
        echo -e "  ${GREEN}BBR 已启用${NC}"
    else
        echo -e "  ${YELLOW}BBR 未启用${NC}"
    fi

    sep
}

#-------------------- 功能 10：系统性能测试 --------------------
performance_test() {
    sep
    echo -e "${BOLD}              系统性能测试${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}选择测试项目：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} CPU 性能测试（sysbench）"
    echo -e "  ${CYAN} 2)${NC} 内存性能测试（sysbench）"
    echo -e "  ${CYAN} 3)${NC} 磁盘 I/O 测试（dd）"
    echo -e "  ${CYAN} 4)${NC} 网络延迟测试（ping 各大网站）"
    echo -e "  ${CYAN} 5)${NC} 全部测试"
    echo ""

    echo -n "请选择 [1-5]（默认 5）: "
    read -r test_choice

    echo ""

    case "$test_choice" in
        1)
            test_cpu
            ;;
        2)
            test_memory
            ;;
        3)
            test_disk
            ;;
        4)
            test_network
            ;;
        *)
            test_cpu
            test_memory
            test_disk
            test_network
            ;;
    esac

    sep
}

test_cpu() {
    echo -e "  ${BOLD}--- CPU 性能测试 ---${NC}"
    echo ""

    if ! command -v sysbench &>/dev/null; then
        info "安装 sysbench..."
        if command -v apt &>/dev/null; then
            apt-get install -y sysbench 2>/dev/null
        elif command -v dnf &>/dev/null; then
            dnf install -y sysbench 2>/dev/null
        elif command -v yum &>/dev/null; then
            yum install -y sysbench 2>/dev/null
        fi
    fi

    if command -v sysbench &>/dev/null; then
        echo -e "  ${CYAN}单线程 CPU 测试：${NC}"
        sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>/dev/null | grep -E "total time|events per second" || echo "  测试失败"
        echo ""
        echo -e "  ${CYAN}多线程 CPU 测试（${OS_CPU} 线程）：${NC}"
        sysbench cpu --cpu-max-prime=20000 --threads="$OS_CPU" run 2>/dev/null | grep -E "total time|events per second" || echo "  测试失败"
    else
        warn "sysbench 未安装，使用替代方法..."
        echo -e "  ${CYAN}CPU 信息：${NC}"
        lscpu 2>/dev/null | grep -E "Model name|CPU MHz|Cache" | while read -r line; do
            echo -e "    ${line}"
        done
    fi
    echo ""
}

test_memory() {
    echo -e "  ${BOLD}--- 内存性能测试 ---${NC}"
    echo ""

    if command -v sysbench &>/dev/null; then
        echo -e "  ${CYAN}内存写入测试：${NC}"
        sysbench memory --memory-block-size=1M --memory-total-size=10G run 2>/dev/null | grep -E "transferred|Operations|MiB/sec" || echo "  测试失败"
    else
        echo -e "  ${CYAN}内存读写速度（dd）：${NC}"
        dd if=/dev/zero of=/tmp/memtest bs=1M count=1024 2>&1 | grep -E "copied" || echo "  测试失败"
        rm -f /tmp/memtest
    fi
    echo ""
}

test_disk() {
    echo -e "  ${BOLD}--- 磁盘 I/O 测试 ---${NC}"
    echo ""

    local test_file="/tmp/disk_test_$$"

    echo -e "  ${CYAN}写入测试（1GB）：${NC}"
    dd if=/dev/zero of="$test_file" bs=1M count=1024 conv=fdatasync 2>&1 | tail -1
    echo ""

    echo -e "  ${CYAN}读取测试（1GB）：${NC}"
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    dd if="$test_file" of=/dev/null bs=1M count=1024 2>&1 | tail -1
    echo ""

    echo -e "  ${CYAN}4K 随机写入测试：${NC}"
    dd if=/dev/zero of="$test_file" bs=4k count=10000 conv=fdatasync 2>&1 | tail -1

    rm -f "$test_file"
    echo ""
}

test_network() {
    echo -e "  ${BOLD}--- 网络延迟测试 ---${NC}"
    echo ""

    local targets=(
        "8.8.8.8:Google DNS"
        "1.1.1.1:Cloudflare DNS"
        "223.5.5.5:阿里 DNS"
        "119.29.29.29:腾讯 DNS"
        "github.com:GitHub"
        "google.com:Google"
    )

    for target in "${targets[@]}"; do
        local ip="${target%%:*}"
        local name="${target##*:}"

        echo -n "  ${name} (${ip}) ... "

        if command -v ping &>/dev/null; then
            local result=$(ping -c 3 -W 2 "$ip" 2>/dev/null | tail -1 | grep -o 'min/avg/max.*' | awk -F'/' '{print $5}')
            if [[ -n "$result" ]]; then
                echo -e "${GREEN}${result}ms${NC}"
            else
                echo -e "${RED}超时${NC}"
            fi
        else
            echo -e "${YELLOW}ping 不可用${NC}"
        fi
    done
    echo ""
}

#-------------------- 功能 11：备份配置 --------------------
do_backup() {
    sep
    echo -e "${BOLD}              备份当前配置${NC}"
    sep
    echo ""

    backup_config

    echo ""
    echo -e "  ${GREEN}${BOLD}● 备份完成！${NC}"

    sep
}

#-------------------- 功能 12：恢复配置 --------------------
do_restore() {
    sep
    echo -e "${BOLD}              恢复优化前配置${NC}"
    sep
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "暂无备份"
        sep
        return
    fi

    echo -e "  ${YELLOW}可用备份：${NC}"
    echo ""

    local idx=1
    declare -A backup_map

    for dir in $(ls -dt "${BACKUP_DIR}"/*/ 2>/dev/null); do
        [[ -d "$dir" ]] || continue
        local dirname=$(basename "$dir")
        echo -e "  ${CYAN}[$idx]${NC} ${dirname}"
        backup_map[$idx]="$dir"
        idx=$((idx + 1))
    done

    echo ""
    echo -n "  输入要恢复的备份编号（或 Enter 取消）: "
    read -r restore_idx

    if [[ -z "$restore_idx" || -z "${backup_map[$restore_idx]}" ]]; then
        info "已取消"
        return
    fi

    local source="${backup_map[$restore_idx]}"

    warn "恢复将覆盖当前所有优化配置！"
    echo ""
    echo -n "  确认恢复？请输入 'YES' 确认: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "恢复配置..."

    # 先备份当前
    local current_bak="${BACKUP_DIR}/pre_restore_${TIMESTAMP}"
    mkdir -p "$current_bak"
    [[ -f "$SYSCTL_CONF" ]] && cp "$SYSCTL_CONF" "$current_bak/"
    [[ -f "$LIMITS_CONF" ]] && cp "$LIMITS_CONF" "$current_bak/"
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "$current_bak/"

    # 恢复
    [[ -f "${source}/sysctl.conf" ]] && cp "${source}/sysctl.conf" "$SYSCTL_CONF"
    [[ -f "${source}/limits.conf" ]] && cp "${source}/limits.conf" "$LIMITS_CONF"
    [[ -f "${source}/resolv.conf" ]] && cp "${source}/resolv.conf" /etc/resolv.conf
    [[ -d "${source}/sysctl.d" ]] && cp -r "${source}/sysctl.d/"* "$SYSCTL_D_DIR/" 2>/dev/null

    sysctl -p 2>/dev/null

    # 解锁 DNS
    chattr -i /etc/resolv.conf 2>/dev/null

    ok "配置已恢复"
    echo -e "  ${BLUE}当前配置已备份到：${NC}${current_bak}"

    sep
}

#-------------------- 功能 13：恢复系统默认值 --------------------
restore_defaults() {
    sep
    echo -e "${BOLD}              恢复系统默认值${NC}"
    sep
    echo ""

    warn "此操作将清除所有优化配置，恢复系统默认值！"
    echo -e "  ${RED}包括：sysctl.conf、limits.conf、DNS 配置${NC}"
    echo ""

    echo -n "  确认恢复系统默认值？请输入 'YES' 确认: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    backup_config

    info "恢复系统默认值..."

    # 清空自定义 sysctl 优化
    if [[ -f "$SYSCTL_CONF" ]]; then
        cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak.${TIMESTAMP}"
        # 保留原始注释，移除我们的优化行
        grep -v "^# =====.*优化" "$SYSCTL_CONF" > "${SYSCTL_CONF}.clean" 2>/dev/null
        mv "${SYSCTL_CONF}.clean" "$SYSCTL_CONF" 2>/dev/null
    fi

    # 移除自定义 limits
    if [[ -f "$LIMITS_CONF" ]]; then
        cp "$LIMITS_CONF" "${LIMITS_CONF}.bak.${TIMESTAMP}"
        sed -i '/^# =====.*优化/d' "$LIMITS_CONF" 2>/dev/null
    fi

    # 移除 limits.d 配置
    rm -f "${LIMITS_D_DIR}/90-nofile.conf" 2>/dev/null

    # 移除 systemd limits
    rm -f /etc/systemd/system.conf.d/limits.conf 2>/dev/null

    # 解锁并恢复 DNS
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

    sysctl -p 2>/dev/null

    echo ""
    echo -e "  ${GREEN}${BOLD}● 系统默认值已恢复！${NC}"
    echo -e "  ${YELLOW}建议重启系统使所有更改生效${NC}"

    sep
}

#-------------------- 主循环 --------------------
main() {
    check_root

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1) auto_optimize ;;
            2) preset_optimize ;;
            3) backup_config; optimize_sysctl; echo ""; ok "内核参数优化完成" ;;
            4) backup_config; optimize_network; echo ""; ok "网络与 TCP 优化完成" ;;
            5) backup_config; optimize_memory; echo ""; ok "内存与交换分区优化完成" ;;
            6) backup_config; optimize_limits; echo ""; ok "文件描述符与系统限制优化完成" ;;
            7) backup_config; optimize_dns; echo ""; ok "DNS 优化完成" ;;
            8) optimize_io ;;
            9) show_current_params ;;
            10) performance_test ;;
            11) do_backup ;;
            12) do_restore ;;
            13) restore_defaults ;;
            0|q|Q)
                echo ""
                info "退出 Linux 优化脚本"
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