#!/bin/bash
#=============================================================================
# 系统信息查看 & 测速 & 回程路由可视化脚本
# 功能：系统信息（CPU/内存/存储/网络）+ 网速测试 + 回程路由可视化
# 用法：chmod +x system_info.sh && sudo ./system_info.sh
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
info()     { echo -e "${GREEN}[信息]${NC} $*"; }
warn()     { echo -e "${YELLOW}[警告]${NC} $*"; }
error()    { echo -e "${RED}[错误]${NC} $*"; }
ok()       { echo -e "${GREEN}  ✓${NC} $*"; }
fail()     { echo -e "${RED}  ✗${NC} $*"; }
sep()      { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
sep_sub()  { echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        SUDO="sudo"
    else
        SUDO=""
    fi
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}      系统信息查看 & 测速 & 回程路由可视化${NC}"
    sep
    echo ""
    echo -e "  ${CYAN} 1)${NC} 系统总览（一键查看全部硬件信息）"
    echo -e "  ${CYAN} 2)${NC} CPU 信息详情"
    echo -e "  ${CYAN} 3)${NC} 内存信息详情"
    echo -e "  ${CYAN} 4)${NC} 存储 / 磁盘信息"
    echo -e "  ${CYAN} 5)${NC} 网络信息 & 公网 IP"
    echo -e "  ${CYAN} 6)${NC} 系统运行状态（负载/启动时间/进程）"
    echo -e "  ${CYAN} 7)${NC} 网络测速（Speedtest）"
    echo -e "  ${CYAN} 8)${NC} 回程路由可视化（NextTrace）"
    echo -e "  ${CYAN} 9)${NC} 流媒体解锁检测"
    echo -e "  ${CYAN}10)${NC} 全部测试（综合跑分）"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：系统总览 --------------------
system_overview() {
    sep
    echo -e "${BOLD}                    系统总览${NC}"
    sep
    echo ""

    # 基础系统信息
    echo -e "${BOLD}【系统信息】${NC}"
    sep_sub
    echo -e "  主机名     : ${CYAN}$(hostname)${NC}"
    echo -e "  操作系统   : ${CYAN}$([[ -f /etc/os-release ]] && . /etc/os-release && echo "$PRETTY_NAME" || echo "Unknown")${NC}"
    echo -e "  内核版本   : ${CYAN}$(uname -r)${NC}"
    echo -e "  系统架构   : ${CYAN}$(uname -m)${NC}"
    echo -e "  运行时间   : ${CYAN}$(uptime -p 2>/dev/null | sed 's/up //')${NC}"
    echo -e "  系统时间   : ${CYAN}$(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
    echo ""

    # CPU 概览
    echo -e "${BOLD}【CPU 信息】${NC}"
    sep_sub
    local cpu_model=$(lscpu | grep "Model name" | sed 's/Model name:\s*//' 2>/dev/null || echo "Unknown")
    local cpu_cores=$(lscpu | grep "^CPU(s)" | awk '{print $2}' 2>/dev/null || echo "?")
    local cpu_sockets=$(lscpu | grep "Socket(s)" | awk '{print $2}' 2>/dev/null || echo "?")
    local cpu_threads=$(lscpu | grep "Thread(s) per core" | awk '{print $4}' 2>/dev/null || echo "?")
    local cpu_freq=$(lscpu | grep "CPU max MHz" | awk '{print $3}' 2>/dev/null)
    local cpu_virt=$(lscpu | grep "Virtualization" | awk '{print $2}' 2>/dev/null)

    echo -e "  型号       : ${CYAN}${cpu_model}${NC}"
    echo -e "  物理CPU    : ${CYAN}${cpu_sockets} 颗${NC}"
    echo -e "  核心数     : ${CYAN}${cpu_cores} 核${NC}"
    echo -e "  每核线程   : ${CYAN}${cpu_threads}${NC}"
    [[ -n "$cpu_freq" ]] && echo -e "  最大频率   : ${CYAN}${cpu_freq} MHz${NC}"
    [[ -n "$cpu_virt" ]] && echo -e "  虚拟化     : ${CYAN}${cpu_virt}${NC}"
    echo -e "  CPU 使用率 : ${CYAN}$(top -bn1 | grep "Cpu(s)" | awk '{print 100-$8"%"}' 2>/dev/null || echo "?")${NC}"
    echo ""

    # 内存概览
    echo -e "${BOLD}【内存信息】${NC}"
    sep_sub
    local mem_total=$(free -b | awk '/Mem:/{print $2}')
    local mem_used=$(free -b | awk '/Mem:/{print $3}')
    local mem_avail=$(free -b | awk '/Mem:/{print $7}')
    local swap_total=$(free -b | awk '/Swap:/{print $2}')
    local swap_used=$(free -b | awk '/Swap:/{print $3}')

    echo -e "  总内存     : ${CYAN}$(bytes_to_human $mem_total)${NC}"
    echo -e "  已使用     : ${YELLOW}$(bytes_to_human $mem_used)${NC} ($(( mem_used * 100 / mem_total ))%)"
    echo -e "  可用       : ${GREEN}$(bytes_to_human $mem_avail)${NC}"
    if [[ "$swap_total" -gt 0 ]] 2>/dev/null; then
        echo -e "  Swap 总量  : ${CYAN}$(bytes_to_human $swap_total)${NC}"
        echo -e "  Swap 已用  : ${YELLOW}$(bytes_to_human $swap_used)${NC}"
    else
        echo -e "  Swap       : ${YELLOW}未启用${NC}"
    fi
    echo ""

    # 存储概览
    echo -e "${BOLD}【存储信息】${NC}"
    sep_sub
    df -h --total 2>/dev/null | grep -E "^/dev|^Filesystem|^total" | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    # 磁盘信息
    echo -e "${BOLD}【物理磁盘】${NC}"
    sep_sub
    if command -v lsblk &>/dev/null; then
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL 2>/dev/null | while read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done
    else
        echo -e "  ${YELLOW}lsblk 不可用${NC}"
    fi
    echo ""

    # 网络概览
    echo -e "${BOLD}【网络信息】${NC}"
    sep_sub
    # 公网 IP
    local pub_ip4=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "获取失败")
    local pub_ip6=$(curl -s6 --max-time 5 https://api6.ipify.org 2>/dev/null || echo "无 IPv6")
    echo -e "  公网 IPv4  : ${CYAN}${pub_ip4}${NC}"
    echo -e "  公网 IPv6  : ${CYAN}${pub_ip6}${NC}"
    echo ""
    echo -e "  ${BLUE}网络接口：${NC}"
    ip -o addr show 2>/dev/null | grep -v "scope link" | grep -v "scope host" | while read -r line; do
        local iface=$(echo "$line" | awk '{print $2}')
        local ipaddr=$(echo "$line" | awk '{print $4}')
        echo -e "    ${CYAN}${iface}${NC}: ${ipaddr}"
    done
    echo ""

    # GPU（如果有）
    if command -v lspci &>/dev/null; then
        local gpu=$(lspci 2>/dev/null | grep -i "vga\|3d\|display")
        if [[ -n "$gpu" ]]; then
            echo -e "${BOLD}【GPU 信息】${NC}"
            sep_sub
            echo -e "  ${CYAN}${gpu}${NC}"
            echo ""
        fi
    fi

    sep
}

#-------------------- 字节转人类可读 --------------------
bytes_to_human() {
    local bytes=$1
    local unit=("B" "KB" "MB" "GB" "TB" "PB")
    local i=0
    while [[ "$bytes" -ge 1024 ]] && [[ $i -lt 5 ]]; do
        bytes=$((bytes / 1024))
        i=$((i + 1))
    done
    echo "${bytes} ${unit[$i]}"
}

#-------------------- 功能 2：CPU 详情 --------------------
cpu_info() {
    sep
    echo -e "${BOLD}                    CPU 详细信息${NC}"
    sep
    echo ""

    echo -e "${BOLD}【CPU 概览】${NC}"
    sep_sub
    lscpu 2>/dev/null | while IFS= read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【CPU 型号与缓存】${NC}"
    sep_sub
    grep -m1 "model name" /proc/cpuinfo | sed 's/^[[:space:]]*//' | while IFS=: read -r k v; do
        echo -e "  ${CYAN}${k}:${v}${NC}"
    done
    grep -m1 "cache size" /proc/cpuinfo | sed 's/^[[:space:]]*//' | while IFS=: read -r k v; do
        echo -e "  ${CYAN}${k}:${v}${NC}"
    done
    echo ""

    echo -e "${BOLD}【实时 CPU 频率（各核心）】${NC}"
    sep_sub
    if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
        for i in $(grep -c ^processor /proc/cpuinfo); do
            local freq_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq"
            if [[ -f "$freq_file" ]]; then
                local freq=$(cat "$freq_file" 2>/dev/null)
                local freq_mhz=$((freq / 1000))
                echo -e "  CPU${i}: ${CYAN}${freq_mhz} MHz${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}无法读取实时频率信息${NC}"
    fi
    echo ""

    echo -e "${BOLD}【CPU 温度】${NC}"
    sep_sub
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        local temp_c=$((temp / 1000))
        local temp_f=$((temp / 555 + 32))
        echo -e "  当前温度: ${CYAN}${temp_c}°C / ${temp_f}°F${NC}"
    else
        echo -e "  ${YELLOW}无法读取温度（可能为虚拟机）${NC}"
    fi
    echo ""

    echo -e "${BOLD}【CPU 使用率 TOP 10 进程】${NC}"
    sep_sub
    ps aux --sort=-%cpu | head -11 | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done

    sep
}

#-------------------- 功能 3：内存详情 --------------------
memory_info() {
    sep
    echo -e "${BOLD}                    内存详细信息${NC}"
    sep
    echo ""

    echo -e "${BOLD}【内存使用概览】${NC}"
    sep_sub
    free -h
    echo ""

    echo -e "${BOLD}【内存详情（dmidecode）】${NC}"
    sep_sub
    if command -v dmidecode &>/dev/null; then
        $SUDO dmidecode -t memory 2>/dev/null | grep -E "Number Of Devices|Size|Type:|Speed|Manufacturer|Serial Number|Locator|Form Factor|Configured Memory Speed" | while read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done
    else
        echo -e "  ${YELLOW}dmidecode 未安装，尝试安装...${NC}"
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case "${ID,,}" in
                ubuntu|debian) apt-get install -y dmidecode 2>/dev/null ;;
                centos|rhel|rocky|almalinux) command -v dnf &>/dev/null && dnf install -y dmidecode || yum install -y dmidecode ;;
            esac
        fi
        $SUDO dmidecode -t memory 2>/dev/null | grep -E "Size|Type:|Speed|Manufacturer|Serial Number|Locator" | while read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done
    fi
    echo ""

    echo -e "${BOLD}【内存使用率 TOP 10 进程】${NC}"
    sep_sub
    ps aux --sort=-%mem | head -11 | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done

    sep
}

#-------------------- 功能 4：存储信息 --------------------
disk_info() {
    sep
    echo -e "${BOLD}                    存储 / 磁盘信息${NC}"
    sep
    echo ""

    echo -e "${BOLD}【磁盘分区使用情况】${NC}"
    sep_sub
    df -hT 2>/dev/null | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【块设备列表】${NC}"
    sep_sub
    if command -v lsblk &>/dev/null; then
        lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINT,FSTYPE,MODEL 2>/dev/null | while read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done
    else
        echo -e "  ${YELLOW}lsblk 不可用${NC}"
    fi
    echo ""

    echo -e "${BOLD}【磁盘 I/O 性能测试】${NC}"
    sep_sub
    echo -e "  ${YELLOW}使用 dd 进行简单写入测试（1GB）...${NC}"
    echo ""
    local dd_result=$(dd if=/dev/zero of=/tmp/disktest.tmp bs=1M count=1024 oflag=direct 2>&1 | tail -1)
    echo -e "  ${CYAN}${dd_result}${NC}"
    rm -f /tmp/disktest.tmp
    echo ""

    echo -e "${BOLD}【硬盘 SMART 信息】${NC}"
    sep_sub
    if command -v smartctl &>/dev/null; then
        for disk in $(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}'); do
            echo -e "  ${BLUE}/dev/${disk}:${NC}"
            $SUDO smartctl -A "/dev/${disk}" 2>/dev/null | tail -15 | while read -r line; do
                echo -e "    ${CYAN}${line}${NC}"
            done
            echo ""
        done
    else
        echo -e "  ${YELLOW}smartctl 未安装（smartmontools 包）${NC}"
        echo -e "  安装: apt install smartmontools 或 yum install smartmontools"
    fi

    sep
}

#-------------------- 功能 5：网络信息 --------------------
network_info() {
    sep
    echo -e "${BOLD}                    网络信息 & 公网 IP${NC}"
    sep
    echo ""

    echo -e "${BOLD}【公网 IP 信息】${NC}"
    sep_sub
    local pub_ip4=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "获取失败")
    local pub_ip6=$(curl -s6 --max-time 5 https://api6.ipify.org 2>/dev/null || echo "无 IPv6")
    echo -e "  公网 IPv4 : ${CYAN}${pub_ip4}${NC}"
    echo -e "  公网 IPv6 : ${CYAN}${pub_ip6}${NC}"

    # IP 归属地查询
    if [[ "$pub_ip4" != "获取失败" ]]; then
        local ip_info=$(curl -s4 --max-time 5 "http://ip-api.com/json/${pub_ip4}?lang=zh-CN" 2>/dev/null)
        if [[ -n "$ip_info" ]]; then
            local country=$(echo "$ip_info" | grep -oP '"country":"[^"]*"' | cut -d'"' -f4)
            local region=$(echo "$ip_info" | grep -oP '"regionName":"[^"]*"' | cut -d'"' -f4)
            local city=$(echo "$ip_info" | grep -oP '"city":"[^"]*"' | cut -d'"' -f4)
            local isp=$(echo "$ip_info" | grep -oP '"isp":"[^"]*"' | cut -d'"' -f4)
            local org=$(echo "$ip_info" | grep -oP '"org":"[^"]*"' | cut -d'"' -f4)
            local as=$(echo "$ip_info" | grep -oP '"as":"[^"]*"' | cut -d'"' -f4)
            echo -e "  归属地   : ${CYAN}${country} ${region} ${city}${NC}"
            echo -e "  ISP     : ${CYAN}${isp}${NC}"
            echo -e "  组织    : ${CYAN}${org}${NC}"
            echo -e "  AS 号   : ${CYAN}${as}${NC}"
        fi
    fi
    echo ""

    echo -e "${BOLD}【网络接口】${NC}"
    sep_sub
    ip -o addr show 2>/dev/null | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【路由表（默认路由）】${NC}"
    sep_sub
    ip route show default 2>/dev/null | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【DNS 配置】${NC}"
    sep_sub
    cat /etc/resolv.conf 2>/dev/null | grep -v "^#" | grep -v "^$" | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【网络连接统计】${NC}"
    sep_sub
    if command -v ss &>/dev/null; then
        echo -e "  TCP 连接总数: ${CYAN}$(ss -t | tail -n +2 | wc -l)${NC}"
        echo -e "  UDP 连接总数: ${CYAN}$(ss -u | tail -n +2 | wc -l)${NC}"
        echo -e "  监听端口数  : ${CYAN}$(ss -tln | tail -n +2 | wc -l)${NC}"
        echo ""
        echo -e "  ${BLUE}监听端口列表：${NC}"
        ss -tlnp 2>/dev/null | while read -r line; do
            echo -e "    ${CYAN}${line}${NC}"
        done
    fi
    echo ""

    echo -e "${BOLD}【网卡流量统计】${NC}"
    sep_sub
    cat /proc/net/dev 2>/dev/null | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done

    sep
}

#-------------------- 功能 6：系统运行状态 --------------------
system_status() {
    sep
    echo -e "${BOLD}                    系统运行状态${NC}"
    sep
    echo ""

    echo -e "${BOLD}【系统负载】${NC}"
    sep_sub
    local load=$(cat /proc/loadavg)
    local load1=$(echo "$load" | awk '{print $1}')
    local load5=$(echo "$load" | awk '{print $2}')
    local load15=$(echo "$load" | awk '{print $3}')
    local cores=$(nproc)
    echo -e "  CPU 核心数  : ${CYAN}${cores}${NC}"
    echo -e "  1 分钟负载  : ${CYAN}${load1}${NC}"
    echo -e "  5 分钟负载  : ${CYAN}${load5}${NC}"
    echo -e "  15分钟负载  : ${CYAN}${load15}${NC}"
    # 负载评估
    local load1_int=$(echo "$load1" | cut -d. -f1)
    if [[ "$load1_int" -lt "$cores" ]]; then
        echo -e "  状态        : ${GREEN}正常${NC}"
    elif [[ "$load1_int" -lt $((cores * 2)) ]]; then
        echo -e "  状态        : ${YELLOW}偏高${NC}"
    else
        echo -e "  状态        : ${RED}过高${NC}"
    fi
    echo ""

    echo -e "${BOLD}【运行时间 & 启动时间】${NC}"
    sep_sub
    echo -e "  运行时间 : ${CYAN}$(uptime -p | sed 's/up //')${NC}"
    if [[ -f /proc/uptime ]]; then
        local uptime_sec=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
        local boot_time=$(($(date +%s) - uptime_sec))
        echo -e "  启动时间 : ${CYAN}$(date -d "@$boot_time" '+%Y-%m-%d %H:%M:%S')${NC}"
    fi
    echo ""

    echo -e "${BOLD}【登录用户】${NC}"
    sep_sub
    who 2>/dev/null | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【进程统计】${NC}"
    sep_sub
    echo -e "  总进程数  : ${CYAN}$(ps aux | wc -l)${NC}"
    echo -e "  运行中    : ${CYAN}$(ps aux | awk '$8 ~ /R/' | wc -l)${NC}"
    echo -e "  睡眠中    : ${CYAN}$(ps aux | awk '$8 ~ /S/' | wc -l)${NC}"
    echo -e "  僵尸进程  : ${YELLOW}$(ps aux | awk '$8 ~ /Z/' | wc -l)${NC}"
    echo ""

    echo -e "${BOLD}【CPU 使用 TOP 5】${NC}"
    sep_sub
    ps aux --sort=-%cpu | head -6 | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    echo -e "${BOLD}【内存使用 TOP 5】${NC}"
    sep_sub
    ps aux --sort=-%mem | head -6 | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done

    sep
}

#-------------------- 功能 7：网络测速 --------------------
speed_test() {
    sep
    echo -e "${BOLD}                    网络测速${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}选择测速方式：${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Speedtest CLI（自动选择最近节点）"
    echo -e "  ${CYAN}2)${NC} Speedtest CLI（指定节点 ID）"
    echo -e "  ${CYAN}3)${NC} bench.sh 综合测速（含国内节点）"
    echo -e "  ${CYAN}4)${NC} 下载速度测试（Cloudflare 100MB）"
    echo ""
    echo -n "请选择 [1/2/3/4]（默认 1）: "
    read -r speed_choice

    echo ""

    case "$speed_choice" in
        2)
            # 指定节点
            echo -e "  ${YELLOW}常用节点 ID 参考：${NC}"
            echo -e "    国内电信: 17145 (上海) / 41110 (广州)"
            echo -e "    国内联通: 42731 (上海) / 24447 (广州)"
            echo -e "    国内移动: 26878 (上海) / 46627 (广州)"
            echo -e "    国外    : 11588 (东京) / 12976 (首尔)"
            echo ""
            echo -n "输入节点 ID: "
            read -r node_id
            install_speedtest
            echo ""
            info "开始测速（节点 $node_id）..."
            $SUDO speedtest --server "$node_id" --format=human-readable
            ;;
        3)
            # bench.sh 综合测速
            info "使用 bench.sh 综合测速..."
            echo ""
            warn "此脚本从网络下载，包含系统信息+网速+磁盘IO测试"
            echo -n "确认运行？(Y/n): "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                echo ""
                if command -v curl &>/dev/null; then
                    bash <(curl -sL https://bench.sh) 2>/dev/null || \
                    bash <(curl -sL https://raw.githubusercontent.com/teddysun/across/master/bench.sh)
                elif command -v wget &>/dev/null; then
                    wget -qO- https://bench.sh | bash 2>/dev/null || \
                    wget -qO- https://raw.githubusercontent.com/teddysun/across/master/bench.sh | bash
                else
                    error "需要 curl 或 wget"
                fi
            fi
            ;;
        4)
            # Cloudflare 下载测试
            info "Cloudflare 100MB 下载测试..."
            echo ""
            echo -e "  当前 IP: ${CYAN}$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null)${NC}"
            echo ""
            if command -v curl &>/dev/null; then
                curl -o /dev/null -w "  下载速度: %{speed_download} bytes/sec\n  总时间 : %{time_total} 秒\n  文件大小: %{size_download} bytes\n" \
                    "https://speed.cloudflare.com/__down?bytes=104857600" 2>/dev/null
            else
                wget -O /dev/null "https://speed.cloudflare.com/__down?bytes=104857600" 2>&1 | tail -3
            fi
            ;;
        *)
            # 自动选择最近节点
            install_speedtest
            echo ""
            info "开始测速（自动选择最近节点）..."
            $SUDO speedtest --format=human-readable
            ;;
    esac

    sep
}

#-------------------- 安装 speedtest --------------------
install_speedtest() {
    if command -v speedtest &>/dev/null; then
        return
    fi

    info "安装 Speedtest CLI (Ookla 官方版)..."
    echo ""

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID,,}" in
            ubuntu|debian|linuxmint|pop)
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | $SUDO bash
                $SUDO apt-get install -y speedtest
                ;;
            centos|rhel|rocky|almalinux|ol|fedora)
                local pm="yum"
                command -v dnf &>/dev/null && pm="dnf"
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | $SUDO bash
                $SUDO $pm install -y speedtest
                ;;
            *)
                # 通用安装方式
                warn "尝试通用安装方式..."
                local arch=$(uname -m)
                local url=""
                case "$arch" in
                    x86_64) url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" ;;
                    aarch64) url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz" ;;
                esac
                if [[ -n "$url" ]]; then
                    curl -sL "$url" -o /tmp/speedtest.tgz
                    tar -xzf /tmp/speedtest.tgz -C /tmp/
                    $SUDO mv /tmp/speedtest /usr/local/bin/
                    $SUDO chmod +x /usr/local/bin/speedtest
                    rm -f /tmp/speedtest.tgz
                fi
                ;;
        esac
    fi

    if command -v speedtest &>/dev/null; then
        ok "Speedtest CLI 安装成功"
    else
        error "Speedtest CLI 安装失败"
    fi
}

#-------------------- 功能 8：回程路由可视化 --------------------
trace_route() {
    sep
    echo -e "${BOLD}              回程路由可视化（NextTrace）${NC}"
    sep
    echo ""

    # 安装 NextTrace
    install_nexttrace

    echo ""
    echo -e "  ${BOLD}选择回程测试目标：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 国内四网（北京/上海/广州/深圳 电信/联通/移动）"
    echo -e "  ${CYAN} 2)${NC} 北京（中国电信 219.141.140.10）"
    echo -e "  ${CYAN} 3)${NC} 上海（中国电信 202.96.209.133）"
    echo -e "  ${CYAN} 4)${NC} 广州（中国电信 202.96.128.86）"
    echo -e "  ${CYAN} 5)${NC} 上海（中国联通 210.21.196.6）"
    echo -e "  ${CYAN} 6)${NC} 广州（中国联通 210.21.4.130）"
    echo -e "  ${CYAN} 7)${NC} 上海（中国移动 211.136.150.66）"
    echo -e "  ${CYAN} 8)${NC} 国际节点（Google 8.8.8.8 / Cloudflare 1.1.1.1）"
    echo -e "  ${CYAN} 9)${NC} 自定义 IP"
    echo -e "  ${CYAN}10)${NC} 地图可视化模式（生成 HTML 地图）"
    echo ""
    echo -n "请选择 [1-10]（默认 1）: "
    read -r trace_choice

    echo ""

    local nt_cmd="nexttrace"

    case "$trace_choice" in
        1)
            info "国内四网回程路由测试..."
            echo ""
            local targets=(
                "219.141.140.10:北京电信"
                "202.96.209.133:上海电信"
                "202.96.128.86:广州电信"
                "123.125.81.6:北京联通"
                "210.21.196.6:上海联通"
                "210.21.4.130:广州联通"
                "211.136.17.107:北京移动"
                "211.136.150.66:上海移动"
            )
            for target in "${targets[@]}"; do
                local ip="${target%%:*}"
                local name="${target##*:}"
                echo ""
                sep_sub
                echo -e "  ${BOLD}→ ${name} (${ip})${NC}"
                sep_sub
                echo ""
                $nt_cmd "$ip" --queries 1 2>/dev/null || warn "路由追踪失败"
                echo ""
            done
            ;;
        2)
            info "北京电信回程路由..."
            echo ""
            $nt_cmd 219.141.140.10 2>/dev/null
            ;;
        3)
            info "上海电信回程路由..."
            echo ""
            $nt_cmd 202.96.209.133 2>/dev/null
            ;;
        4)
            info "广州电信回程路由..."
            echo ""
            $nt_cmd 202.96.128.86 2>/dev/null
            ;;
        5)
            info "上海联通回程路由..."
            echo ""
            $nt_cmd 210.21.196.6 2>/dev/null
            ;;
        6)
            info "广州联通回程路由..."
            echo ""
            $nt_cmd 210.21.4.130 2>/dev/null
            ;;
        7)
            info "上海移动回程路由..."
            echo ""
            $nt_cmd 211.136.150.66 2>/dev/null
            ;;
        8)
            info "国际节点回程路由..."
            echo ""
            sep_sub
            echo -e "  ${BOLD}→ Google DNS (8.8.8.8)${NC}"
            sep_sub
            $nt_cmd 8.8.8.8 2>/dev/null
            echo ""
            sep_sub
            echo -e "  ${BOLD}→ Cloudflare DNS (1.1.1.1)${NC}"
            sep_sub
            $nt_cmd 1.1.1.1 2>/dev/null
            ;;
        9)
            echo -n "输入目标 IP 或域名: "
            read -r custom_ip
            if [[ -n "$custom_ip" ]]; then
                info "回程路由到 ${custom_ip}..."
                echo ""
                $nt_cmd "$custom_ip" 2>/dev/null
            else
                warn "未输入地址"
            fi
            ;;
        10)
            info "地图可视化模式（生成 HTML 地图）..."
            echo ""
            echo -e "  ${YELLOW}此功能将生成 HTML 格式的路由地图可视化页面${NC}"
            echo -n "输入目标 IP（默认 8.8.8.8）: "
            read -r map_ip
            map_ip="${map_ip:-8.8.8.8}"
            echo ""
            info "正在追踪并生成地图..."
            $nt_cmd "$map_ip" --map 2>/dev/null || {
                warn "地图模式需要 LeoMoeAPI 支持"
                echo -e "  ${CYAN}提示：${NC}使用 nexttrace --map <IP> 生成可视化地图链接"
                echo ""
                $nt_cmd "$map_ip" 2>/dev/null
            }
            ;;
    esac

    sep
}

#-------------------- 安装 NextTrace --------------------
install_nexttrace() {
    if command -v nexttrace &>/dev/null; then
        ok "NextTrace 已安装"
        return
    fi

    info "安装 NextTrace..."
    echo ""

    # 检测架构
    local arch=$(uname -m)
    local nt_arch=""
    case "$arch" in
        x86_64)  nt_arch="amd64" ;;
        aarch64) nt_arch="arm64" ;;
        *) warn "不支持的架构: $arch，尝试继续..." ;;
    esac

    # 使用官方安装脚本
    if command -v curl &>/dev/null; then
        curl -sL https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${nt_arch} -o /tmp/nexttrace 2>/dev/null || \
        curl -sL "https://raw.githubusercontent.com/nxtrace/NTrace-core/main/nt_install.sh" | bash 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -qO /tmp/nexttrace "https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${nt_arch}" 2>/dev/null || \
        wget -qO- "https://raw.githubusercontent.com/nxtrace/NTrace-core/main/nt_install.sh" | bash 2>/dev/null
    fi

    # 安装到系统路径
    if [[ -f /tmp/nexttrace ]]; then
        $SUDO mv /tmp/nexttrace /usr/local/bin/nexttrace
        $SUDO chmod +x /usr/local/bin/nexttrace
    fi

    if command -v nexttrace &>/dev/null; then
        ok "NextTrace 安装成功"
    else
        warn "自动安装失败，请手动安装：https://github.com/nxtrace/NTrace-core"
        echo -e "  ${CYAN}手动安装：${NC}"
        echo -e "    curl -sL https://raw.githubusercontent.com/nxtrace/NTrace-core/main/nt_install.sh | bash"
    fi
}

#-------------------- 功能 9：流媒体解锁检测 --------------------
streaming_check() {
    sep
    echo -e "${BOLD}                    流媒体解锁检测${NC}"
    sep
    echo ""

    info "使用流媒体检测脚本..."
    echo ""
    warn "此脚本从网络下载（RealIPovich/RegionRestrictionCheck）"
    echo -n "确认运行？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""

    if command -v bash &>/dev/null; then
        bash <(curl -sSL https://media.ispvps.com) 2>/dev/null || \
        bash <(curl -sSL https://raw.githubusercontent.com/1-stream/RegionRestrictionCheck/main/check.sh) 2>/dev/null || \
        warn "流媒体检测脚本下载失败，请检查网络"
    fi

    sep
}

#-------------------- 功能 10：全部测试 --------------------
full_test() {
    sep
    echo -e "${BOLD}                    全部综合测试${NC}"
    sep
    echo ""

    warn "此功能将依次执行：系统信息 → 网络测速 → 回程路由"
    echo -n "确认运行全部测试？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "【1/3】系统信息总览..."
    echo ""
    system_overview

    echo ""
    info "【2/3】网络测速..."
    echo ""
    install_speedtest
    echo ""
    $SUDO speedtest --format=human-readable 2>/dev/null || warn "测速失败"

    echo ""
    info "【3/3】回程路由（国内四网）..."
    echo ""
    install_nexttrace
    echo ""
    local targets=(
        "219.141.140.10:北京电信"
        "202.96.209.133:上海电信"
        "202.96.128.86:广州电信"
        "210.21.196.6:上海联通"
        "211.136.150.66:上海移动"
    )
    for target in "${targets[@]}"; do
        local ip="${target%%:*}"
        local name="${target##*:}"
        echo ""
        sep_sub
        echo -e "  ${BOLD}→ ${name} (${ip})${NC}"
        sep_sub
        nexttrace "$ip" --queries 1 2>/dev/null || warn "追踪失败"
        echo ""
    done

    sep
    echo -e "${GREEN}${BOLD}              全部测试完成！${NC}"
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
            1)  system_overview ;;
            2)  cpu_info ;;
            3)  memory_info ;;
            4)  disk_info ;;
            5)  network_info ;;
            6)  system_status ;;
            7)  speed_test ;;
            8)  trace_route ;;
            9)  streaming_check ;;
            10) full_test ;;
            0|q|Q)
                echo ""
                info "退出系统信息查看脚本"
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
