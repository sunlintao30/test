#!/bin/bash
#=============================================================================
# 文件同步软件安装与管理脚本
# 功能：Syncthing / rclone / Resilio Sync 一键安装与管理
# 支持：Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora
# 用法：chmod +x file_sync.sh && sudo ./file_sync.sh
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本：sudo $0"
        exit 1
    fi
}

#-------------------- 全局变量 --------------------
SYNC_BASE_DIR="/srv/sync"
ARCH=$(uname -m)

#-------------------- 获取系统信息 --------------------
get_system_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_NAME="${PRETTY_NAME}"
    else
        OS_ID="unknown"
        OS_NAME="未知系统"
    fi

    case "$ARCH" in
        x86_64)  ARCH_MAP="amd64" ;;
        aarch64) ARCH_MAP="arm64" ;;
        armv7l)  ARCH_MAP="arm" ;;
        *)       ARCH_MAP="$ARCH" ;;
    esac
}

#-------------------- 包管理 --------------------
pkg_install() {
    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop)
            apt-get update -qq 2>/dev/null
            apt-get install -y "$@" 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux|ol|fedora)
            local pm="yum"
            command -v dnf &>/dev/null && pm="dnf"
            $pm install -y "$@" 2>/dev/null
            ;;
    esac
}

#-------------------- 防火墙放行 --------------------
open_firewall_port() {
    local port=$1
    local proto=${2:-tcp}

    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${proto}" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "${port}/${proto}" 2>/dev/null
    fi
}

#-------------------- 检测安装状态 --------------------
check_installed() {
    SYNCTHING_STATUS="未安装"
    RCLONE_STATUS="未安装"
    RESILIO_STATUS="未安装"

    command -v syncthing &>/dev/null && SYNCTHING_STATUS="已安装"
    systemctl is-active --quiet syncthing@root 2>/dev/null && SYNCTHING_STATUS="运行中"

    command -v rclone &>/dev/null && RCLONE_STATUS="已安装"

    command -v rslsync &>/dev/null && RESILIO_STATUS="已安装"
    systemctl is-active --quiet resilio-sync 2>/dev/null && RESILIO_STATUS="运行中"
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    get_system_info
    check_installed

    sep
    echo -e "${BOLD}          文件同步软件安装与管理${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}系统：${NC}${OS_NAME}  |  ${BLUE}架构：${NC}${ARCH}"
    echo -e "  ${BLUE}同步目录：${NC}${SYNC_BASE_DIR}"
    echo ""

    echo -e "  ${BOLD}软件状态：${NC}"
    echo -e "  ${CYAN}Syncthing    ${NC} ${GREEN}${SYNCTHING_STATUS}${NC}    ${CYAN}rclone    ${NC} ${GREEN}${RCLONE_STATUS}${NC}    ${CYAN}Resilio Sync ${NC} ${GREEN}${RESILIO_STATUS}${NC}"
    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【Syncthing - P2P 去中心化同步】${NC}"
    echo -e "  ${CYAN} 1)${NC} 安装 Syncthing（官方最新版）"
    echo -e "  ${CYAN} 2)${NC} 配置 Syncthing（Web UI / 目录 / 远程访问）"
    echo -e "  ${CYAN} 3)${NC} 启动/停止/重启 Syncthing"
    echo -e "  ${CYAN} 4)${NC} 查看 Syncthing 状态与日志"
    echo -e "  ${CYAN} 5)${NC} 卸载 Syncthing"
    echo ""

    echo -e "  ${CYAN}【rclone - 云存储同步工具】${NC}"
    echo -e "  ${CYAN} 6)${NC} 安装 rclone（官方最新版）"
    echo -e "  ${CYAN} 7)${NC} 配置 rclone 远程存储"
    echo -e "  ${CYAN} 8)${NC} rclone 同步/挂载操作"
    echo -e "  ${CYAN} 9)${NC} 设置 rclone 定时同步任务"
    echo -e " ${CYAN}10)${NC} 卸载 rclone"
    echo ""

    echo -e "  ${CYAN}【Resilio Sync - BT 协议同步】${NC}"
    echo -e " ${CYAN}11)${NC} 安装 Resilio Sync"
    echo -e " ${CYAN}12)${NC} 配置 Resilio Sync"
    echo -e " ${CYAN}13)${NC} 启动/停止/重启 Resilio Sync"
    echo -e " ${CYAN}14)${NC} 卸载 Resilio Sync"
    echo ""

    echo -e "  ${CYAN}【综合】${NC}"
    echo -e " ${CYAN}15)${NC} 对比三个同步软件"
    echo -e " ${CYAN} 0)${NC} 退出"
    echo ""
    sep
    echo -n "请输入选项: "
}

#=============================================================================
#                           Syncthing
#=============================================================================

#-------------------- 功能 1：安装 Syncthing --------------------
install_syncthing() {
    sep
    echo -e "${BOLD}          安装 Syncthing${NC}"
    sep
    echo ""

    if command -v syncthing &>/dev/null; then
        warn "Syncthing 已安装: $(syncthing --version 2>/dev/null | head -1)"
        echo -n "  是否重新安装/更新？(y/N): "
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    fi

    echo -e "  ${BOLD}选择安装方式：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 官方 APT/YUM 仓库 ${GREEN}（推荐，自动更新）${NC}"
    echo -e "  ${CYAN} 2)${NC} 官方二进制包 ${YELLOW}（手动下载）${NC}"
    echo -e "  ${CYAN} 3)${NC} Docker 容器方式"
    echo ""
    echo -n "请选择 [1-3]（默认 1）: "
    read -r install_method
    install_method="${install_method:-1}"

    case "$install_method" in
        1)
            info "通过官方仓库安装..."
            case "$OS_ID" in
                ubuntu|debian|linuxmint|pop)
                    # 添加 Syncthing 官方 APT 仓库
                    curl -s -o /usr/share/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg 2>/dev/null
                    echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net syncthing stable" > /etc/apt/sources.list.d/syncthing.list
                    apt-get update -qq 2>/dev/null
                    apt-get install -y syncthing 2>/dev/null
                    ;;
                *)
                    # RHEL 系列使用二进制方式
                    install_syncthing_binary
                    ;;
            esac
            ;;
        2)
            install_syncthing_binary
            ;;
        3)
            install_syncthing_docker
            ;;
    esac

    if command -v syncthing &>/dev/null; then
        ok "Syncthing 安装成功: $(syncthing --version 2>/dev/null | head -1)"
        echo ""
        echo -e "  ${YELLOW}请使用菜单 2 配置 Syncthing${NC}"
    else
        error "安装失败"
    fi

    sep
}

#-------------------- Syncthing 二进制安装 --------------------
install_syncthing_binary() {
    info "下载 Syncthing 最新版..."

    # 获取最新版本号
    local latest_ver=$(curl -sL "https://api.github.com/repos/syncthing/syncthing/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*"' | head -1 | sed 's/"tag_name":"//;s/"//')
    latest_ver="${latest_ver:-v1.29.2}"

    info "最新版本: ${latest_ver}"

    local download_url="https://github.com/syncthing/syncthing/releases/download/${latest_ver}/syncthing-linux-${ARCH_MAP}-${latest_ver}.tar.gz"

    # 国内加速
    echo -n "  是否使用国内加速？(Y/n): "
    read -r use_mirror
    if [[ ! "$use_mirror" =~ ^[Nn]$ ]]; then
        download_url="https://ghp.ci/${download_url}"
    fi

    local tmp_file="/tmp/syncthing-${latest_ver}.tar.gz"
    info "下载中: ${download_url}"
    curl -L -o "$tmp_file" "$download_url" 2>/dev/null || wget -q -O "$tmp_file" "$download_url" 2>/dev/null

    if [[ ! -f "$tmp_file" ]] || [[ ! -s "$tmp_file" ]]; then
        error "下载失败"
        return 1
    fi

    info "解压安装..."
    tar -xzf "$tmp_file" -C /tmp/
    local extract_dir="/tmp/syncthing-linux-${ARCH_MAP}-${latest_ver}"
    cp "${extract_dir}/syncthing" /usr/local/bin/
    chmod +x /usr/local/bin/syncthing
    rm -rf "$tmp_file" "$extract_dir"

    # 安装 systemd 服务
    cat > /etc/systemd/system/syncthing@.service <<'EOF'
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization for %I
Documentation=man:syncthing(1)
After=network.target

[Service]
User=%i
ExecStart=/usr/local/bin/syncthing -no-browser -no-restart -logflags=3
Restart=on-failure
RestartSec=5
SuccessExitStatus=3 4 5 RestartForceExitStatus=6

# 硬化安全
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

#-------------------- Syncthing Docker 安装 --------------------
install_syncthing_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker 未安装，请先运行 Docker 安装脚本"
        return 1
    fi

    info "通过 Docker 安装 Syncthing..."

    mkdir -p "${SYNC_BASE_DIR}/syncthing/config"
    mkdir -p "${SYNC_BASE_DIR}/syncthing/data"

    docker run -d \
        --name syncthing \
        --restart=unless-stopped \
        -p 8384:8384 \
        -p 22000:22000/tcp \
        -p 22000:22000/udp \
        -p 21027:21027/udp \
        -v "${SYNC_BASE_DIR}/syncthing/config:/config" \
        -v "${SYNC_BASE_DIR}/syncthing/data:/data" \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=Asia/Shanghai \
        linuxserver/syncthing:latest 2>/dev/null || lscr.io/linuxserver/syncthing:latest

    ok "Syncthing Docker 容器已启动"
    echo -e "  ${BLUE}Web UI: ${NC}http://$(hostname -I 2>/dev/null | awk '{print $1}'):8384"
    echo -e "  ${BLUE}配置目录: ${NC}${SYNC_BASE_DIR}/syncthing/config"
    echo -e "  ${BLUE}数据目录: ${NC}${SYNC_BASE_DIR}/syncthing/data"

    open_firewall_port 8384
    open_firewall_port 22000
    open_firewall_port 21027 udp
}

#-------------------- 功能 2：配置 Syncthing --------------------
configure_syncthing() {
    sep
    echo -e "${BOLD}          配置 Syncthing${NC}"
    sep
    echo ""

    if ! command -v syncthing &>/dev/null; then
        error "Syncthing 未安装"
        return
    fi

    # 首次启动生成配置
    local config_dir="${HOME}/.config/syncthing"
    if [[ ! -f "${config_dir}/config.xml" ]]; then
        info "首次启动生成配置..."
        syncthing generate 2>/dev/null || syncthing -generate "${config_dir}" 2>/dev/null
    fi

    local config_file="${config_dir}/config.xml"

    echo -e "  ${BOLD}配置选项：${NC}"
    echo ""

    # Web UI 地址
    echo -n "  Web UI 监听地址（默认 0.0.0.0:8384，留空使用默认）: "
    read -r gui_addr
    if [[ -n "$gui_addr" ]]; then
        sed -i "s|<address>127.0.0.1:8384</address>|<address>${gui_addr}</address>|" "$config_file" 2>/dev/null
        sed -i "s|<address>0.0.0.0:8384</address>|<address>${gui_addr}</address>|" "$config_file" 2>/dev/null
    else
        sed -i "s|<address>127.0.0.1:8384</address>|<address>0.0.0.0:8384</address>|" "$config_file" 2>/dev/null
    fi
    ok "Web UI 地址已设置为 0.0.0.0:8384（允许远程访问）"

    # 同步目录
    echo -n "  默认同步目录（默认 ${SYNC_BASE_DIR}/syncthing）: "
    read -r sync_dir
    sync_dir="${sync_dir:-${SYNC_BASE_DIR}/syncthing}"
    mkdir -p "$sync_dir"

    # 设置 systemd 服务
    info "配置 systemd 服务..."
    systemctl enable "syncthing@root" 2>/dev/null
    systemctl restart "syncthing@root" 2>/dev/null

    # 防火墙
    open_firewall_port 8384
    open_firewall_port 22000
    open_firewall_port 21027 udp

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    local device_id=$(syncthing -device-id 2>/dev/null || echo "启动后查看")

    echo ""
    echo -e "  ${GREEN}${BOLD}● Syncthing 配置完成！${NC}"
    echo -e "  ${BLUE}Web UI: ${NC}http://${server_ip}:8384"
    echo -e "  ${BLUE}同步目录: ${NC}${sync_dir}"
    echo -e "  ${BLUE}设备 ID: ${NC}${device_id}"
    echo -e "  ${BLUE}配置文件: ${NC}${config_file}"
    echo ""
    echo -e "  ${YELLOW}提示：${NC}"
    echo -e "  1. 在浏览器打开 Web UI 完成初始设置"
    echo -e "  2. 添加共享文件夹时选择 ${sync_dir}"
    echo -e "  3. 在其他设备上添加本设备 ID 进行同步"

    sep
}

#-------------------- 功能 3：Syncthing 服务控制 --------------------
control_syncthing() {
    sep
    echo -e "${BOLD}          Syncthing 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态    ${CYAN} 5)${NC} 开机自启"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start syncthing@root; ok "已启动" ;;
        2) systemctl stop syncthing@root; ok "已停止" ;;
        3) systemctl restart syncthing@root; ok "已重启" ;;
        4) systemctl status syncthing@root --no-pager -l ;;
        5)
            systemctl enable syncthing@root
            ok "已设置开机自启"
            ;;
    esac
    sep
}

#-------------------- 功能 4：查看 Syncthing 状态 --------------------
show_syncthing_status() {
    sep
    echo -e "${BOLD}          Syncthing 状态${NC}"
    sep
    echo ""

    if ! command -v syncthing &>/dev/null; then
        warn "Syncthing 未安装"
        return
    fi

    echo -e "  ${BOLD}版本：${NC}"
    syncthing --version 2>/dev/null
    echo ""

    echo -e "  ${BOLD}服务状态：${NC}"
    systemctl is-active --quiet syncthing@root 2>/dev/null && echo -e "  ${GREEN}● 运行中${NC}" || echo -e "  ${RED}○ 未运行${NC}"
    echo ""

    echo -e "  ${BOLD}设备 ID：${NC}"
    syncthing -device-id 2>/dev/null || echo "  无法获取（服务未运行）"
    echo ""

    echo -e "  ${BOLD}最近日志（20 条）：${NC}"
    journalctl -u syncthing@root -n 20 --no-pager 2>/dev/null || warn "无日志"

    sep
}

#-------------------- 功能 5：卸载 Syncthing --------------------
uninstall_syncthing() {
    sep
    echo -e "${BOLD}          卸载 Syncthing${NC}"
    sep
    echo ""

    warn "将卸载 Syncthing（配置和数据保留）"
    echo -n "  确认卸载？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    systemctl stop syncthing@root 2>/dev/null
    systemctl disable syncthing@root 2>/dev/null
    rm -f /etc/systemd/system/syncthing@.service
    systemctl daemon-reload

    # Docker 容器
    docker stop syncthing 2>/dev/null && docker rm syncthing 2>/dev/null

    # 二进制
    rm -f /usr/local/bin/syncthing

    # APT 包
    apt-get remove -y syncthing 2>/dev/null || true

    # APT 仓库
    rm -f /etc/apt/sources.list.d/syncthing.list 2>/dev/null
    rm -f /usr/share/keyrings/syncthing-archive-keyring.gpg 2>/dev/null

    ok "Syncthing 已卸载"
    echo -e "  ${YELLOW}配置和数据保留在 ${HOME}/.config/syncthing 和 ${SYNC_BASE_DIR}/syncthing${NC}"

    sep
}

#=============================================================================
#                           rclone
#=============================================================================

#-------------------- 功能 6：安装 rclone --------------------
install_rclone() {
    sep
    echo -e "${BOLD}          安装 rclone${NC}"
    sep
    echo ""

    if command -v rclone &>/dev/null; then
        warn "rclone 已安装: $(rclone version 2>/dev/null | head -1)"
        echo -n "  是否重新安装/更新？(y/N): "
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    fi

    echo -e "  ${BOLD}选择安装方式：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 官方一键脚本 ${GREEN}（推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} 手动下载二进制"
    echo -e "  ${CYAN} 3)${NC} 包管理器安装"
    echo ""
    echo -n "请选择 [1-3]（默认 1）: "
    read -r install_method
    install_method="${install_method:-1}"

    case "$install_method" in
        1)
            info "使用官方一键安装脚本..."
            curl -sSL https://rclone.org/install.sh | bash 2>/dev/null
            ;;
        2)
            info "手动下载二进制..."
            local latest_ver=$(curl -sL "https://api.github.com/repos/rclone/rclone/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*"' | head -1 | sed 's/"tag_name":"//;s/"//')
            latest_ver="${latest_ver:-v1.68.2}"

            local download_url="https://github.com/rclone/rclone/releases/download/${latest_ver}/rclone-${latest_ver}-linux-${ARCH_MAP}.zip"

            echo -n "  是否使用国内加速？(Y/n): "
            read -r use_mirror
            [[ ! "$use_mirror" =~ ^[Nn]$ ]] && download_url="https://ghp.ci/${download_url}"

            curl -L -o /tmp/rclone.zip "$download_url" 2>/dev/null
            cd /tmp && unzip -o rclone.zip 2>/dev/null
            cp "rclone-${latest_ver}-linux-${ARCH_MAP}/rclone" /usr/local/bin/
            chmod +x /usr/local/bin/rclone
            rm -rf /tmp/rclone.zip /tmp/rclone-*
            cd -
            ;;
        3)
            info "通过包管理器安装..."
            pkg_install rclone
            ;;
    esac

    if command -v rclone &>/dev/null; then
        ok "rclone 安装成功"
        rclone version 2>/dev/null | head -3
        echo ""
        echo -e "  ${YELLOW}请使用菜单 7 配置远程存储${NC}"
    else
        error "安装失败"
    fi

    sep
}

#-------------------- 功能 7：配置 rclone 远程存储 --------------------
configure_rclone() {
    sep
    echo -e "${BOLD}          配置 rclone 远程存储${NC}"
    sep
    echo ""

    if ! command -v rclone &>/dev/null; then
        error "rclone 未安装"
        return
    fi

    echo -e "  ${BOLD}当前已配置的远程存储：${NC}"
    echo ""
    rclone listremotes 2>/dev/null || echo "  无"
    echo ""

    echo -e "  ${BOLD}支持的存储类型：${NC}"
    echo -e "  ${CYAN}Google Drive, OneDrive, Dropbox, S3, WebDAV, FTP, SFTP${NC}"
    echo -e "  ${CYAN}阿里云盘, 百度网盘, 腾讯微云, 坚果云, 本地存储${NC}"
    echo ""

    echo -e "  ${YELLOW}即将进入 rclone 交互式配置向导${NC}"
    echo -e "  ${YELLOW}按照提示操作即可${NC}"
    echo ""
    echo -n "  开始配置？(Y/n): "
    read -r confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return

    echo ""
    rclone config

    echo ""
    ok "配置完成"
    echo ""
    echo -e "  ${BOLD}当前远程存储：${NC}"
    rclone listremotes 2>/dev/null

    sep
}

#-------------------- 功能 8：rclone 同步/挂载操作 --------------------
rclone_operations() {
    sep
    echo -e "${BOLD}          rclone 同步/挂载操作${NC}"
    sep
    echo ""

    if ! command -v rclone &>/dev/null; then
        error "rclone 未安装"
        return
    fi

    local remotes=$(rclone listremotes 2>/dev/null)
    if [[ -z "$remotes" ]]; then
        warn "暂无配置的远程存储，请先使用菜单 7 配置"
        return
    fi

    echo -e "  ${BOLD}可用远程存储：${NC}"
    echo "$remotes" | while read -r r; do
        echo -e "    ${CYAN}${r}${NC}"
    done
    echo ""

    echo -e "  ${BOLD}选择操作：${NC}"
    echo -e "  ${CYAN} 1)${NC} 同步本地 → 远程（sync）"
    echo -e "  ${CYAN} 2)${NC} 同步远程 → 本地（sync）"
    echo -e "  ${CYAN} 3)${NC} 复制本地 → 远程（copy）"
    echo -e "  ${CYAN} 4)${NC} 复制远程 → 本地（copy）"
    echo -e "  ${CYAN} 5)${NC} 双向同步（bisync）"
    echo -e "  ${CYAN} 6)${NC} 挂载远程存储（mount）"
    echo -e "  ${CYAN} 7)${NC} 查看远程文件列表（ls）"
    echo ""
    echo -n "请选择: "
    read -r op_choice

    case "$op_choice" in
        1|2|3|4|5|6|7)
            echo -n "  远程存储名称（如 mydrive:）: "
            read -r remote_name
            echo -n "  本地路径: "
            read -r local_path

            case "$op_choice" in
                1)
                    info "同步本地 → ${remote_name}..."
                    rclone sync "$local_path" "$remote_name" -P --transfers 4
                    ;;
                2)
                    info "同步 ${remote_name} → 本地..."
                    rclone sync "$remote_name" "$local_path" -P --transfers 4
                    ;;
                3)
                    info "复制本地 → ${remote_name}..."
                    rclone copy "$local_path" "$remote_name" -P --transfers 4
                    ;;
                4)
                    info "复制 ${remote_name} → 本地..."
                    rclone copy "$remote_name" "$local_path" -P --transfers 4
                    ;;
                5)
                    info "双向同步..."
                    rclone bisync "$local_path" "$remote_name" --resync -P
                    ;;
                6)
                    mkdir -p "$local_path"
                    info "挂载 ${remote_name} → ${local_path}..."
                    # 安装 fuse
                    pkg_install fuse fuse3 2>/dev/null

                    # 创建 systemd 挂载服务
                    local escaped_name=$(echo "$remote_name" | tr ':' '_' | tr '/' '_')
                    cat > "/etc/systemd/system/rclone-mount-${escaped_name}.service" <<EOF
[Unit]
Description=rclone mount ${remote_name}
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount ${remote_name} ${local_path} \
    --allow-other \
    --allow-non-empty \
    --vfs-cache-mode full \
    --vfs-cache-max-size 1G \
    --dir-cache-time 24h \
    --buffer-size 32M
ExecStop=/bin/fusermount -uz ${local_path}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
                    systemctl daemon-reload
                    systemctl enable "rclone-mount-${escaped_name}"
                    systemctl start "rclone-mount-${escaped_name}"
                    ok "已挂载 ${remote_name} → ${local_path}"
                    ;;
                7)
                    rclone ls "$remote_name" --max-depth 2 2>/dev/null | head -50
                    ;;
            esac
            ok "操作完成"
            ;;
    esac

    sep
}

#-------------------- 功能 9：rclone 定时同步 --------------------
setup_rclone_cron() {
    sep
    echo -e "${BOLD}          设置 rclone 定时同步任务${NC}"
    sep
    echo ""

    if ! command -v rclone &>/dev/null; then
        error "rclone 未安装"
        return
    fi

    local remotes=$(rclone listremotes 2>/dev/null)
    if [[ -z "$remotes" ]]; then
        warn "暂无配置的远程存储"
        return
    fi

    echo -e "  ${BOLD}可用远程存储：${NC}"
    echo "$remotes"
    echo ""

    echo -n "  远程存储名称（如 mydrive:backup）: "
    read -r remote_name
    echo -n "  本地路径: "
    read -r local_path
    echo -n "  同步方向（1=本地→远程, 2=远程→本地, 默认 1）: "
    read -r direction
    direction="${direction:-1}"

    local sync_cmd=""
    if [[ "$direction" == "2" ]]; then
        sync_cmd="rclone sync ${remote_name} ${local_path} --transfers 4 --log-file /var/log/rclone_sync.log"
    else
        sync_cmd="rclone sync ${local_path} ${remote_name} --transfers 4 --log-file /var/log/rclone_sync.log"
    fi

    echo ""
    echo -e "  ${BOLD}选择同步频率：${NC}"
    echo -e "  ${CYAN} 1)${NC} 每 30 分钟"
    echo -e "  ${CYAN} 2)${NC} 每小时"
    echo -e "  ${CYAN} 3)${NC} 每 6 小时"
    echo -e "  ${CYAN} 4)${NC} 每天 凌晨 3 点"
    echo -e "  ${CYAN} 5)${NC} 自定义"
    echo ""
    echo -n "请选择 [1-5]（默认 2）: "
    read -r freq_choice
    freq_choice="${freq_choice:-2}"

    local cron_expr=""
    case "$freq_choice" in
        1) cron_expr="*/30 * * * *" ;;
        2) cron_expr="0 * * * *" ;;
        3) cron_expr="0 */6 * * *" ;;
        4) cron_expr="0 3 * * *" ;;
        5)
            echo -n "  输入 cron 表达式（分 时 日 月 周）: "
            read -r cron_expr
            ;;
    esac

    # 创建 systemd timer（比 cron 更可靠）
    local job_name="rclone-sync-$(echo "$remote_name" | tr ':/' '-')"

    cat > "/etc/systemd/system/${job_name}.service" <<EOF
[Unit]
Description=rclone sync ${remote_name}
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${sync_cmd}'
TimeoutStartSec=3600
EOF

    cat > "/etc/systemd/system/${job_name}.timer" <<EOF
[Unit]
Description=rclone sync timer for ${remote_name}

[Timer]
OnBootSec=5min
OnUnitActiveSec=$([[ "$freq_choice" == "1" ]] && echo "30min" || ([[ "$freq_choice" == "2" ]] && echo "1h" || ([[ "$freq_choice" == "3" ]] && echo "6h" || echo "24h")))
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 对于每日指定时间的，使用 OnCalendar
    if [[ "$freq_choice" == "4" ]]; then
        sed -i "s|OnUnitActiveSec=24h|OnCalendar=*-*-* 03:00:00|" "/etc/systemd/system/${job_name}.timer"
    elif [[ "$freq_choice" == "5" ]]; then
        sed -i "/OnUnitActiveSec/d" "/etc/systemd/system/${job_name}.timer"
        echo "OnCalendar=${cron_expr}" >> "/etc/systemd/system/${job_name}.timer"
    fi

    systemctl daemon-reload
    systemctl enable "${job_name}.timer"
    systemctl start "${job_name}.timer"

    ok "定时同步任务已创建"
    echo -e "  ${BLUE}任务名称：${NC}${job_name}"
    echo -e "  ${BLUE}同步命令：${NC}${sync_cmd}"
    echo -e "  ${BLUE}日志文件：${NC}/var/log/rclone_sync.log"
    echo -e "  ${YELLOW}查看状态：systemctl status ${job_name}.timer${NC}"

    sep
}

#-------------------- 功能 10：卸载 rclone --------------------
uninstall_rclone() {
    sep
    echo -e "${BOLD}          卸载 rclone${NC}"
    sep
    echo ""

    warn "将卸载 rclone（配置保留）"
    echo -n "  确认卸载？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    rm -f /usr/local/bin/rclone /usr/bin/rclone

    # 停止所有 rclone 挂载
    systemctl list-units --type=service | grep "rclone-mount" | awk '{print $1}' | while read -r svc; do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
        rm -f "/etc/systemd/system/${svc}"
    done

    # 停止定时任务
    systemctl list-units --type=timer | grep "rclone-sync" | awk '{print $1}' | while read -r tmr; do
        systemctl stop "$tmr" 2>/dev/null
        systemctl disable "$tmr" 2>/dev/null
        rm -f "/etc/systemd/system/${tmr}"
    done

    systemctl daemon-reload
    ok "rclone 已卸载"
    echo -e "  ${YELLOW}配置文件保留在 ${HOME}/.config/rclone/rclone.conf${NC}"

    sep
}

#=============================================================================
#                           Resilio Sync
#=============================================================================

#-------------------- 功能 11：安装 Resilio Sync --------------------
install_resilio() {
    sep
    echo -e "${BOLD}          安装 Resilio Sync${NC}"
    sep
    echo ""

    if command -v rslsync &>/dev/null; then
        warn "Resilio Sync 已安装"
        echo -n "  是否重新安装？(y/N): "
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    fi

    echo -e "  ${BOLD}选择安装方式：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 官方 APT/YUM 仓库 ${GREEN}（推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} 手动下载二进制"
    echo -e "  ${CYAN} 3)${NC} Docker 容器方式"
    echo ""
    echo -n "请选择 [1-3]（默认 1）: "
    read -r install_method
    install_method="${install_method:-1}"

    case "$install_method" in
        1)
            info "通过官方仓库安装..."
            case "$OS_ID" in
                ubuntu|debian|linuxmint|pop)
                    curl -sL "https://linux-packages.resilio.com/resilio-sync/key.asc" | gpg --dearmor -o /usr/share/keyrings/resilio-sync.gpg 2>/dev/null
                    echo "deb [signed-by=/usr/share/keyrings/resilio-sync.gpg] https://linux-packages.resilio.com/resilio-sync/deb resilio-sync main" > /etc/apt/sources.list.d/resilio-sync.list
                    apt-get update -qq 2>/dev/null
                    apt-get install -y resilio-sync 2>/dev/null
                    ;;
                *)
                    cat > /etc/yum.repos.d/resilio-sync.repo <<'EOF'
[resilio-sync]
name=Resilio Sync
baseurl=https://linux-packages.resilio.com/resilio-sync/rpm/$basearch
enabled=1
gpgcheck=1
EOF
                    rpm --import https://linux-packages.resilio.com/resilio-sync/key.asc 2>/dev/null
                    pkg_install resilio-sync
                    ;;
            esac
            ;;
        2)
            info "手动下载二进制..."
            local download_url="https://download-cdn.resilio.com/stable/linux-${ARCH_MAP}/rslsync"
            curl -L -o /usr/local/bin/rslsync "$download_url" 2>/dev/null || wget -q -O /usr/local/bin/rslsync "$download_url"
            chmod +x /usr/local/bin/rslsync

            # 创建配置
            mkdir -p /etc/resilio-sync
            /usr/local/bin/rslsync --dump-sample-config > /etc/resilio-sync/sync.conf 2>/dev/null
            ;;
        3)
            install_resilio_docker
            return
            ;;
    esac

    if command -v rslsync &>/dev/null || [[ -f /usr/bin/rslsync ]]; then
        ok "Resilio Sync 安装成功"
        echo ""
        echo -e "  ${YELLOW}请使用菜单 12 配置 Resilio Sync${NC}"
    else
        error "安装失败"
    fi

    sep
}

#-------------------- Resilio Docker 安装 --------------------
install_resilio_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker 未安装"
        return 1
    fi

    info "通过 Docker 安装 Resilio Sync..."

    mkdir -p "${SYNC_BASE_DIR}/resilio/config"
    mkdir -p "${SYNC_BASE_DIR}/resilio/data"

    docker run -d \
        --name resilio-sync \
        --restart=unless-stopped \
        -p 8888:8888 \
        -p 9999:9999 \
        -v "${SYNC_BASE_DIR}/resilio/config:/config" \
        -v "${SYNC_BASE_DIR}/resilio/data:/sync" \
        -e TZ=Asia/Shanghai \
        linuxserver/resilio-sync:latest 2>/dev/null

    ok "Resilio Sync Docker 容器已启动"
    echo -e "  ${BLUE}Web UI: ${NC}http://$(hostname -I 2>/dev/null | awk '{print $1}'):8888"

    open_firewall_port 8888
    open_firewall_port 9999
}

#-------------------- 功能 12：配置 Resilio Sync --------------------
configure_resilio() {
    sep
    echo -e "${BOLD}          配置 Resilio Sync${NC}"
    sep
    echo ""

    # 检查安装
    local rslsync_path=$(command -v rslsync 2>/dev/null || echo "/usr/bin/rslsync")
    if [[ ! -f "$rslsync_path" ]]; then
        rslsync_path="/usr/local/bin/rslsync"
    fi

    if [[ ! -f "$rslsync_path" ]]; then
        error "Resilio Sync 未安装"
        return
    fi

    echo -n "  同步数据目录（默认 ${SYNC_BASE_DIR}/resilio）: "
    read -r sync_dir
    sync_dir="${sync_dir:-${SYNC_BASE_DIR}/resilio}"
    mkdir -p "$sync_dir"

    echo -n "  Web UI 端口（默认 8888）: "
    read -r webui_port
    webui_port="${webui_port:-8888}"

    echo -n "  Web UI 用户名（默认 admin）: "
    read -r webui_user
    webui_user="${webui_user:-admin}"

    echo -n "  Web UI 密码: "
    read -r -s webui_pass
    echo ""

    info "生成配置文件..."

    local config_dir="/etc/resilio-sync"
    mkdir -p "$config_dir"

    # 生成配置
    cat > "${config_dir}/sync.conf" <<EOF
{
    "listening_port": 0,
    "storage_path": "${config_dir}",
    "pid_file": "${config_dir}/rslsync.pid",

    "webui": {
        "listen": "0.0.0.0:${webui_port}",
        "login": "${webui_user}",
        "password": "${webui_pass}",
        "allow_empty_password": false
    },

    "directory_root": "${sync_dir}",
    "directory_root_policy": "belowroot",

    "folders": {
        "default": {
            "dir": "${sync_dir}",
            "selective_sync": false
        }
    }
}
EOF

    # 创建 systemd 服务
    cat > /etc/systemd/system/resilio-sync.service <<EOF
[Unit]
Description=Resilio Sync Service
After=network.target

[Service]
Type=forking
PIDFile=${config_dir}/rslsync.pid
ExecStart=${rslsync_path} --config ${config_dir}/sync.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable resilio-sync 2>/dev/null
    systemctl restart resilio-sync 2>/dev/null

    # 防火墙
    open_firewall_port "$webui_port"

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● Resilio Sync 配置完成！${NC}"
    echo -e "  ${BLUE}Web UI: ${NC}http://${server_ip}:${webui_port}"
    echo -e "  ${BLUE}用户名: ${NC}${webui_user}"
    echo -e "  ${BLUE}同步目录: ${NC}${sync_dir}"
    echo -e "  ${BLUE}配置文件: ${NC}${config_dir}/sync.conf"
    echo ""
    echo -e "  ${YELLOW}提示：在浏览器打开 Web UI，添加同步文件夹和设备${NC}"

    sep
}

#-------------------- 功能 13：Resilio 服务控制 --------------------
control_resilio() {
    sep
    echo -e "${BOLD}          Resilio Sync 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start resilio-sync; ok "已启动" ;;
        2) systemctl stop resilio-sync; ok "已停止" ;;
        3) systemctl restart resilio-sync; ok "已重启" ;;
        4) systemctl status resilio-sync --no-pager -l ;;
    esac
    sep
}

#-------------------- 功能 14：卸载 Resilio Sync --------------------
uninstall_resilio() {
    sep
    echo -e "${BOLD}          卸载 Resilio Sync${NC}"
    sep
    echo ""

    warn "将卸载 Resilio Sync（数据保留）"
    echo -n "  确认卸载？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    systemctl stop resilio-sync 2>/dev/null
    systemctl disable resilio-sync 2>/dev/null
    rm -f /etc/systemd/system/resilio-sync.service
    systemctl daemon-reload

    docker stop resilio-sync 2>/dev/null && docker rm resilio-sync 2>/dev/null

    rm -f /usr/local/bin/rslsync /usr/bin/rslsync
    rm -rf /etc/resilio-sync
    rm -f /etc/apt/sources.list.d/resilio-sync.list 2>/dev/null
    rm -f /etc/yum.repos.d/resilio-sync.repo 2>/dev/null

    apt-get remove -y resilio-sync 2>/dev/null || true

    ok "Resilio Sync 已卸载"

    sep
}

#=============================================================================
#                           综合对比
#=============================================================================

#-------------------- 功能 15：对比三个同步软件 --------------------
compare_sync_tools() {
    sep
    echo -e "${BOLD}          文件同步软件对比${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}┌──────────────┬──────────────────┬──────────────────┬──────────────────┐${NC}"
    echo -e "  ${BOLD}│     特性     │    Syncthing     │     rclone       │  Resilio Sync    │${NC}"
    echo -e "  ${BOLD}├──────────────┼──────────────────┼──────────────────┼──────────────────┤${NC}"
    echo -e "  │ 同步方式     │ P2P 去中心化      │ 客户端-服务器     │ P2P (BT协议)      │"
    echo -e "  │ 传输协议     │ TCP/UDP/QUIC      │ HTTP/HTTPS/SFTP   │ UDP (uTP)         │"
    echo -e "  │ 加密         │ TLS 端到端加密    │ TLS + 可选加密    │ 端到端加密        │"
    echo -e "  │ 云存储支持   │ 否                │ 40+ 种云存储      │ 否                │"
    echo -e "  │ 局域网加速   │ 是                │ 否                │ 是                │"
    echo -e "  │ 增量同步     │ 是（块级）        │ 是（块级）        │ 是（块级）        │"
    echo -e "  │ 双向同步     │ 是                │ 是（bisync）      │ 是                │"
    echo -e "  │ 选择性同步   │ 是                │ 是（filter）      │ 是                │"
    echo -e "  │ 文件版本     │ 是                │ 否                │ 是                │"
    echo -e "  │ 开源         │ 是 (MPL-2.0)      │ 是 (MIT)          │ 否（闭源免费）    │"
    echo -e "  │ 资源占用     │ 低                │ 极低              │ 中                │"
    echo -e "  │ 跨平台       │ 全平台            │ 全平台            │ 全平台            │"
    echo -e "  │ Web UI       │ 是                │ 否                │ 是                │"
    echo -e "  │ 中文支持     │ 是                │ 英文              │ 是                │"
    echo -e "  ${BOLD}└──────────────┴──────────────────┴──────────────────┴──────────────────┘${NC}"
    echo ""

    echo -e "  ${BOLD}使用建议：${NC}"
    echo ""
    echo -e "  ${CYAN}Syncthing${NC} - ${GREEN}适合：设备间文件同步，无需云存储${NC}"
    echo -e "    优势：完全去中心化，无需中央服务器，隐私安全"
    echo -e "    场景：多台电脑/手机之间同步文件"
    echo ""
    echo -e "  ${CYAN}rclone${NC}     - ${GREEN}适合：与云存储交互（Google Drive/OneDrive/S3等）${NC}"
    echo -e "    优势：支持 40+ 种云存储，命令行强大，可挂载"
    echo -e "    场景：备份到云、从云恢复、迁移数据"
    echo ""
    echo -e "  ${CYAN}Resilio${NC}    - ${GREEN}适合：大文件/大量文件快速同步${NC}"
    echo -e "    优势：基于 BT 协议，超大文件传输快，支持选择性同步"
    echo -e "    场景：同步视频库、大型项目文件"

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
            1) install_syncthing ;;
            2) configure_syncthing ;;
            3) control_syncthing ;;
            4) show_syncthing_status ;;
            5) uninstall_syncthing ;;
            6) install_rclone ;;
            7) configure_rclone ;;
            8) rclone_operations ;;
            9) setup_rclone_cron ;;
            10) uninstall_rclone ;;
            11) install_resilio ;;
            12) configure_resilio ;;
            13) control_resilio ;;
            14) uninstall_resilio ;;
            15) compare_sync_tools ;;
            0|q|Q)
                echo ""
                info "退出文件同步管理脚本"
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