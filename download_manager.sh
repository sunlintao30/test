#!/bin/bash
#=============================================================================
# 远程下载软件安装与管理脚本
# 功能：Aria2(+AriaNg) / qBittorrent-nox / Transmission 一键安装与管理
# 支持：Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora
# 用法：chmod +x download_manager.sh && sudo ./download_manager.sh
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
DOWNLOAD_DIR="/srv/downloads"
ARIA2_CONF_DIR="/etc/aria2"
ARIA2_LOG="/var/log/aria2.log"
ARIA2_SESSION="/etc/aria2/aria2.session"
ARIA2_DIR="${DOWNLOAD_DIR}/aria2"
QBT_DIR="${DOWNLOAD_DIR}/qbittorrent"
TR_DIR="${DOWNLOAD_DIR}/transmission"

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
    ARIA2_STATUS="未安装"
    QBT_STATUS="未安装"
    TR_STATUS="未安装"

    command -v aria2c &>/dev/null && ARIA2_STATUS="已安装"
    systemctl is-active --quiet aria2 2>/dev/null && ARIA2_STATUS="运行中"

    command -v qbittorrent-nox &>/dev/null && QBT_STATUS="已安装"
    systemctl is-active --quiet qbittorrent-nox 2>/dev/null && QBT_STATUS="运行中"

    command -v transmission-daemon &>/dev/null && TR_STATUS="已安装"
    systemctl is-active --quiet transmission-daemon 2>/dev/null && TR_STATUS="运行中"
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    get_system_info
    check_installed

    sep
    echo -e "${BOLD}          远程下载软件安装与管理${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}系统：${NC}${OS_NAME}"
    echo -e "  ${BLUE}下载目录：${NC}${DOWNLOAD_DIR}"
    echo ""

    echo -e "  ${BOLD}软件状态：${NC}"
    echo -e "  ${CYAN}Aria2         ${NC} ${GREEN}${ARIA2_STATUS}${NC}"
    echo -e "  ${CYAN}qBittorrent   ${NC} ${GREEN}${QBT_STATUS}${NC}"
    echo -e "  ${CYAN}Transmission  ${NC} ${GREEN}${TR_STATUS}${NC}"
    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【Aria2 + AriaNg（多协议下载）】${NC}"
    echo -e "  ${CYAN} 1)${NC} 一键安装 Aria2 + AriaNg"
    echo -e "  ${CYAN} 2)${NC} 配置 Aria2（RPC/下载/BT/限速）"
    echo -e "  ${CYAN} 3)${NC} 启动/停止/重启 Aria2"
    echo -e "  ${CYAN} 4)${NC} 查看 Aria2 状态"
    echo -e "  ${CYAN} 5)${NC} 卸载 Aria2"
    echo ""

    echo -e "  ${CYAN}【qBittorrent-nox（BT 下载）】${NC}"
    echo -e "  ${CYAN} 6)${NC} 一键安装 qBittorrent-nox"
    echo -e "  ${CYAN} 7)${NC} 配置 qBittorrent"
    echo -e "  ${CYAN} 8)${NC} 启动/停止/重启 qBittorrent"
    echo -e "  ${CYAN} 9)${NC} 查看 qBittorrent 状态"
    echo -e " ${CYAN}10)${NC} 卸载 qBittorrent"
    echo ""

    echo -e "  ${CYAN}【Transmission（轻量 BT）】${NC}"
    echo -e " ${CYAN}11)${NC} 一键安装 Transmission"
    echo -e " ${CYAN}12)${NC} 配置 Transmission"
    echo -e " ${CYAN}13)${NC} 启动/停止/重启 Transmission"
    echo -e " ${CYAN}14)${NC} 查看 Transmission 状态"
    echo -e " ${CYAN}15)${NC} 卸载 Transmission"
    echo ""

    echo -e "  ${CYAN}【综合管理】${NC}"
    echo -e " ${CYAN}16)${NC} 一键安装全部下载软件"
    echo -e " ${CYAN}17)${NC} 对比三个下载软件"
    echo -e " ${CYAN} 0)${NC} 退出"
    echo ""
    sep
    echo -n "请输入选项: "
}

#=============================================================================
#                           Aria2 + AriaNg
#=============================================================================

#-------------------- 功能 1：一键安装 Aria2 --------------------
install_aria2() {
    sep
    echo -e "${BOLD}          一键安装 Aria2 + AriaNg${NC}"
    sep
    echo ""

    # 安装 aria2
    info "安装 Aria2..."
    pkg_install aria2 nginx
    ok "Aria2 安装完成"

    # 创建目录
    mkdir -p "$ARIA2_CONF_DIR" "$ARIA2_DIR"
    mkdir -p "$DOWNLOAD_DIR"
    chmod -R 755 "$DOWNLOAD_DIR"

    # 生成 RPC 密钥
    local rpc_secret=$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -1)

    # 创建配置文件
    cat > "${ARIA2_CONF_DIR}/aria2.conf" <<EOF
# ===== Aria2 完整配置 =====
# 基本设置
dir=${ARIA2_DIR}
log=${ARIA2_LOG}
log-level=warn
daemon=true

# RPC 设置
enable-rpc=true
rpc-listen-all=true
rpc-listen-port=6800
rpc-secret=${rpc_secret}
rpc-max-request-size=10M
rpc-save-upload-metadata=true

# 下载设置
max-concurrent-downloads=5
continue=true
always-resume=true
max-connection-per-server=16
min-split-size=10M
split=16
max-tries=5
retry-wait=10
connect-timeout=30
timeout=60
max-overall-download-limit=0
max-download-limit=0

# BT 设置
enable-dht=true
enable-dht6=true
bt-enable-lpd=true
enable-peer-exchange=true
bt-max-peers=55
follow-torrent=true
listen-port=6881-6999
dht-listen-port=6881-6999
dht-listen-port6=6881-6999
bt-request-peer-speed-limit=50K
seed-ratio=1.0
seed-time=60
peer-id-prefix=-Aria2-

# BT 做种设置
bt-seed-unverified=true
bt-save-metadata=true
bt-remove-unselected-file=true

# 磁盘缓存
disk-cache=32M
file-allocation=falloc
preallocation=0

# 会话保存
input-file=${ARIA2_SESSION}
save-session=${ARIA2_SESSION}
save-session-interval=60

# IPv6
disable-ipv6=false

# 速度测试
max-overall-upload-limit=1M
EOF

    # 创建空会话文件
    touch "$ARIA2_SESSION"

    # 创建 systemd 服务
    cat > /etc/systemd/system/aria2.service <<'EOF'
[Unit]
Description=Aria2 Download Manager
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/aria2c --conf-path=/etc/aria2/aria2.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable aria2 2>/dev/null
    systemctl start aria2 2>/dev/null
    ok "Aria2 服务已启动"

    # 安装 AriaNg
    echo ""
    info "安装 AriaNg Web 面板..."

    local ariang_dir="/usr/share/nginx/html/ariang"
    mkdir -p "$ariang_dir"

    local ariang_url="https://github.com/mayswind/AriaNg/releases/download/1.3.7/AriaNg-1.3.7.zip"

    echo -n "  是否使用国内加速下载 AriaNg？(Y/n): "
    read -r use_mirror
    if [[ ! "$use_mirror" =~ ^[Nn]$ ]]; then
        ariang_url="https://ghp.ci/${ariang_url}"
    fi

    curl -L -o /tmp/ariang.zip "$ariang_url" 2>/dev/null || wget -q -O /tmp/ariang.zip "$ariang_url"
    unzip -o /tmp/ariang.zip -d "$ariang_dir" 2>/dev/null
    rm -f /tmp/ariang.zip

    # Nginx 配置 AriaNg
    cat > /etc/nginx/conf.d/ariang.conf <<EOF
server {
    listen 6801;
    server_name _;

    root ${ariang_dir};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Aria2 RPC 反向代理（可选，增加安全性）
    location /jsonrpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

    nginx -t 2>/dev/null && systemctl enable nginx 2>/dev/null && systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
    ok "AriaNg 已部署"

    # 防火墙
    open_firewall_port 6800
    open_firewall_port 6801
    open_firewall_port 6881-6999

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● Aria2 + AriaNg 安装完成！${NC}"
    echo -e "  ${BLUE}AriaNg 面板：${NC}http://${server_ip}:6801"
    echo -e "  ${BLUE}RPC 端口  ：${NC}6800"
    echo -e "  ${BLUE}RPC 密钥  ：${NC}${MAGENTA}${rpc_secret}${NC}"
    echo -e "  ${BLUE}下载目录  ：${NC}${ARIA2_DIR}"
    echo ""
    echo -e "  ${YELLOW}首次打开 AriaNg 后：${NC}"
    echo -e "  1. 点击左侧 RPC → 设置 Aria2 RPC"
    echo -e "  2. RPC 地址填 http://${server_ip}:6800/jsonrpc"
    echo -e "  3. RPC 密钥填 ${rpc_secret}"

    # 保存密钥供后续查看
    echo "$rpc_secret" > "${ARIA2_CONF_DIR}/.rpc_secret"
    chmod 600 "${ARIA2_CONF_DIR}/.rpc_secret"

    sep
}

#-------------------- 功能 2：配置 Aria2 --------------------
configure_aria2() {
    sep
    echo -e "${BOLD}          配置 Aria2${NC}"
    sep
    echo ""

    if ! command -v aria2c &>/dev/null; then
        error "Aria2 未安装"
        return
    fi

    local conf="${ARIA2_CONF_DIR}/aria2.conf"
    if [[ ! -f "$conf" ]]; then
        warn "未找到配置文件，请先安装 Aria2"
        return
    fi

    echo -e "  ${BOLD}选择配置项：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 修改 RPC 密钥"
    echo -e "  ${CYAN} 2)${NC} 修改下载目录"
    echo -e "  ${CYAN} 3)${NC} 修改并发/线程数"
    echo -e "  ${CYAN} 4)${NC} 修改限速（下载/上传）"
    echo -e "  ${CYAN} 5)${NC} 修改 BT 监听端口"
    echo -e "  ${CYAN} 6)${NC} 修改 RPC 监听端口"
    echo -e "  ${CYAN} 7)${NC} 查看完整配置"
    echo -e "  ${CYAN} 8)${NC} 查看 RPC 密钥"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  新 RPC 密钥: "
            read -r new_secret
            sed -i "s/^rpc-secret=.*/rpc-secret=${new_secret}/" "$conf"
            echo "$new_secret" > "${ARIA2_CONF_DIR}/.rpc_secret"
            chmod 600 "${ARIA2_CONF_DIR}/.rpc_secret"
            systemctl restart aria2 2>/dev/null
            ok "RPC 密钥已修改"
            ;;
        2)
            echo -n "  新下载目录: "
            read -r new_dir
            mkdir -p "$new_dir"
            sed -i "s|^dir=.*|dir=${new_dir}|" "$conf"
            systemctl restart aria2 2>/dev/null
            ok "下载目录已修改"
            ;;
        3)
            echo -n "  最大并发下载数（当前: $(grep max-concurrent-downloads "$conf" | cut -d= -f2)）: "
            read -r val
            sed -i "s/^max-concurrent-downloads=.*/max-concurrent-downloads=${val}/" "$conf"
            echo -n "  单服务器连接数（当前: $(grep max-connection-per-server "$conf" | cut -d= -f2)）: "
            read -r val
            sed -i "s/^max-connection-per-server=.*/max-connection-per-server=${val}/" "$conf"
            echo -n "  分片数（当前: $(grep '^split=' "$conf" | cut -d= -f2)）: "
            read -r val
            sed -i "s/^split=.*/split=${val}/" "$conf"
            systemctl restart aria2 2>/dev/null
            ok "并发配置已修改"
            ;;
        4)
            echo -n "  全局下载限速（0=不限，如 5M）: "
            read -r dl_limit
            echo -n "  全局上传限速（0=不限，如 1M）: "
            read -r ul_limit
            sed -i "s/^max-overall-download-limit=.*/max-overall-download-limit=${dl_limit}/" "$conf"
            sed -i "s/^max-overall-upload-limit=.*/max-overall-upload-limit=${ul_limit}/" "$conf"
            systemctl restart aria2 2>/dev/null
            ok "限速配置已修改"
            ;;
        5)
            echo -n "  BT 监听端口范围（如 6881-6999）: "
            read -r bt_port
            sed -i "s|^listen-port=.*|listen-port=${bt_port}|" "$conf"
            sed -i "s|^dht-listen-port=.*|dht-listen-port=${bt_port}|" "$conf"
            sed -i "s|^dht-listen-port6=.*|dht-listen-port6=${bt_port}|" "$conf"
            systemctl restart aria2 2>/dev/null
            ok "BT 端口已修改"
            ;;
        6)
            echo -n "  RPC 监听端口（当前: $(grep rpc-listen-port "$conf" | cut -d= -f2)）: "
            read -r rpc_port
            sed -i "s/^rpc-listen-port=.*/rpc-listen-port=${rpc_port}/" "$conf"
            systemctl restart aria2 2>/dev/null
            open_firewall_port "$rpc_port"
            ok "RPC 端口已修改"
            ;;
        7)
            echo ""
            cat "$conf" | grep -v "^$" | grep -v "^#" | while read -r line; do
                echo -e "  ${CYAN}${line}${NC}"
            done
            ;;
        8)
            if [[ -f "${ARIA2_CONF_DIR}/.rpc_secret" ]]; then
                echo -e "  ${MAGENTA}$(cat "${ARIA2_CONF_DIR}/.rpc_secret")${NC}"
            else
                local secret=$(grep "^rpc-secret=" "$conf" | cut -d= -f2)
                echo -e "  ${MAGENTA}${secret}${NC}"
            fi
            ;;
    esac

    sep
}

#-------------------- 功能 3：Aria2 服务控制 --------------------
control_aria2() {
    sep
    echo -e "${BOLD}          Aria2 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start aria2; ok "已启动" ;;
        2) systemctl stop aria2; ok "已停止" ;;
        3) systemctl restart aria2; ok "已重启" ;;
        4) systemctl status aria2 --no-pager -l ;;
    esac
    sep
}

#-------------------- 功能 4：查看 Aria2 状态 --------------------
show_aria2_status() {
    sep
    echo -e "${BOLD}          Aria2 状态${NC}"
    sep
    echo ""

    if ! command -v aria2c &>/dev/null; then
        warn "Aria2 未安装"
        return
    fi

    echo -e "  ${BOLD}版本：${NC}$(aria2c --version | head -1)"
    echo ""

    echo -e "  ${BOLD}服务状态：${NC}"
    systemctl is-active --quiet aria2 2>/dev/null && echo -e "  ${GREEN}● 运行中${NC}" || echo -e "  ${RED}○ 未运行${NC}"
    echo ""

    local conf="${ARIA2_CONF_DIR}/aria2.conf"
    if [[ -f "$conf" ]]; then
        echo -e "  ${BOLD}配置概要：${NC}"
        echo -e "  ${CYAN}RPC 端口 ：${NC}$(grep rpc-listen-port "$conf" | cut -d= -f2)"
        echo -e "  ${CYAN}下载目录 ：${NC}$(grep "^dir=" "$conf" | cut -d= -f2)"
        echo -e "  ${CYAN}并发下载数：${NC}$(grep max-concurrent-downloads "$conf" | cut -d= -f2)"
        echo -e "  ${CYAN}单服务器连接：${NC}$(grep max-connection-per-server "$conf" | cut -d= -f2)"
        echo -e "  ${CYAN}BT 端口  ：${NC}$(grep "^listen-port=" "$conf" | cut -d= -f2)"
        echo ""

        if [[ -f "${ARIA2_CONF_DIR}/.rpc_secret" ]]; then
            echo -e "  ${BOLD}RPC 密钥：${NC}${MAGENTA}$(cat "${ARIA2_CONF_DIR}/.rpc_secret")${NC}"
        fi
    fi

    echo ""
    echo -e "  ${BOLD}磁盘使用：${NC}"
    df -h "$ARIA2_DIR" 2>/dev/null | tail -1

    sep
}

#-------------------- 功能 5：卸载 Aria2 --------------------
uninstall_aria2() {
    sep
    echo -e "${BOLD}          卸载 Aria2${NC}"
    sep
    echo ""

    echo -n "  确认卸载 Aria2？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    systemctl stop aria2 2>/dev/null
    systemctl disable aria2 2>/dev/null
    rm -f /etc/systemd/system/aria2.service
    systemctl daemon-reload

    rm -rf "$ARIA2_CONF_DIR" /usr/share/nginx/html/ariang /etc/nginx/conf.d/ariang.conf
    apt-get remove -y aria2 2>/dev/null || yum remove -y aria2 2>/dev/null || true

    ok "Aria2 已卸载"
    echo -e "  ${YELLOW}下载文件保留在 ${ARIA2_DIR}${NC}"

    sep
}

#=============================================================================
#                           qBittorrent-nox
#=============================================================================

#-------------------- 功能 6：一键安装 qBittorrent --------------------
install_qbittorrent() {
    sep
    echo -e "${BOLD}          一键安装 qBittorrent-nox${NC}"
    sep
    echo ""

    info "安装 qBittorrent-nox..."

    # 创建专用用户（安全最佳实践）
    if ! id qbittorrent-nox &>/dev/null; then
        useradd -r -m -d /var/opt/qbittorrent-nox -s /usr/sbin/nologin -g qbittorrent-nox qbittorrent-nox 2>/dev/null || {
            groupadd qbittorrent-nox 2>/dev/null
            useradd -r -m -d /var/opt/qbittorrent-nox -s /usr/sbin/nologin -g qbittorrent-nox qbittorrent-nox
        }
    fi

    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq 2>/dev/null
            # 先添加 universe 源
            add-apt-repository -y universe 2>/dev/null || true
            apt-get update -qq 2>/dev/null
            apt-get install -y qbittorrent-nox 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux)
            # EPEL 源
            pkg_install epel-release
            pkg_install qbittorrent-nox 2>/dev/null || {
                warn "官方仓库无 qBittorrent，尝试手动安装..."
                install_qbittorrent_static
            }
            ;;
        fedora)
            pkg_install qbittorrent-nox 2>/dev/null || install_qbittorrent_static
            ;;
        *)
            warn "尝试手动安装 qBittorrent-nox..."
            install_qbittorrent_static
            ;;
    esac

    if ! command -v qbittorrent-nox &>/dev/null; then
        error "qBittorrent-nox 安装失败"
        return
    fi

    ok "qBittorrent-nox 安装完成"

    # 创建下载目录
    mkdir -p "$QBT_DIR"
    chown -R qbittorrent-nox:qbittorrent-nox "$QBT_DIR" 2>/dev/null

    # Web UI 端口
    echo -n "  Web UI 端口（默认 8080）: "
    read -r webui_port
    webui_port="${webui_port:-8080}"

    # 创建 systemd 服务
    cat > /etc/systemd/system/qbittorrent-nox.service <<EOF
[Unit]
Description=qBittorrent-nox Daemon
After=network-online.target

[Service]
Type=forking
User=qbittorrent-nox
Group=qbittorrent-nox
ExecStart=/usr/bin/qbittorrent-nox -d --webui-port=${webui_port}
ExecStop=/usr/bin/kill -QUIT \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable qbittorrent-nox 2>/dev/null
    systemctl start qbittorrent-nox 2>/dev/null
    ok "qBittorrent 服务已启动"

    # 防火墙
    open_firewall_port "$webui_port"
    open_firewall_port 6881-6999

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● qBittorrent-nox 安装完成！${NC}"
    echo -e "  ${BLUE}Web UI   ：${NC}http://${server_ip}:${webui_port}"
    echo -e "  ${BLUE}默认账户 ：${NC}${CYAN}admin / adminadmin${NC}"
    echo -e "  ${BLUE}下载目录 ：${NC}${QBT_DIR}"
    echo ""
    echo -e "  ${RED}⚠ 重要：首次登录后请立即修改默认密码！${NC}"

    sep
}

# qBittorrent 静态编译安装
install_qbittorrent_static() {
    info "使用静态编译版本安装 qBittorrent-nox..."

    local arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="arm64" ;;
        *)       arch="x86_64" ;;
    esac

    local install_url="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download/qbittorrent-nox-${arch}-musl-linux.zip"

    echo -n "  是否使用国内加速？(Y/n): "
    read -r use_mirror
    [[ ! "$use_mirror" =~ ^[Nn]$ ]] && install_url="https://ghp.ci/${install_url}"

    curl -L -o /tmp/qbt.zip "$install_url" 2>/dev/null || wget -q -O /tmp/qbt.zip "$install_url"

    cd /tmp && unzip -o qbt.zip 2>/dev/null

    # 安装二进制
    local extracted=$(find /tmp -name "qbittorrent-nox" -type f 2>/dev/null | head -1)
    if [[ -n "$extracted" ]]; then
        cp "$extracted" /usr/local/bin/qbittorrent-nox
        chmod +x /usr/local/bin/qbittorrent-nox
        ok "qBittorrent-nox 静态版安装成功"

        # 更新 systemd 服务中的路径
        sed -i 's|/usr/bin/qbittorrent-nox|/usr/local/bin/qbittorrent-nox|' /etc/systemd/system/qbittorrent-nox.service 2>/dev/null
    else
        error "解压失败，找不到二进制文件"
    fi

    rm -rf /tmp/qbt.zip /tmp/qbittorrent-nox* /tmp/install*
    cd -
}

#-------------------- 功能 7：配置 qBittorrent --------------------
configure_qbittorrent() {
    sep
    echo -e "${BOLD}          配置 qBittorrent${NC}"
    sep
    echo ""

    if ! command -v qbittorrent-nox &>/dev/null; then
        error "qBittorrent 未安装"
        return
    fi

    echo -e "  ${BOLD}选择配置项：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 修改 Web UI 端口"
    echo -e "  ${CYAN} 2)${NC} 修改下载目录"
    echo -e "  ${CYAN} 3)${NC} 修改默认密码"
    echo -e "  ${CYAN} 4)${NC} 设置上传/下载限速"
    echo -e "  ${CYAN} 5)${NC} 查看 Web UI 地址和密码"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  新 Web UI 端口: "
            read -r new_port
            systemctl stop qbittorrent-nox 2>/dev/null
            sed -i "s/--webui-port=[0-9]*/--webui-port=${new_port}/" /etc/systemd/system/qbittorrent-nox.service
            systemctl daemon-reload
            systemctl start qbittorrent-nox 2>/dev/null
            open_firewall_port "$new_port"
            ok "Web UI 端口已修改为 ${new_port}"
            ;;
        2)
            echo -n "  新下载目录: "
            read -r new_dir
            mkdir -p "$new_dir"
            chown -R qbittorrent-nox:qbittorrent-nox "$new_dir" 2>/dev/null
            ok "下载目录已修改（请在 Web UI 中同步更改）"
            ;;
        3)
            echo -e "  ${YELLOW}请通过 Web UI 修改密码：${NC}"
            echo -e "  ${CYAN}工具 → 选项 → Web UI → 认证${NC}"
            ;;
        4)
            echo -e "  ${YELLOW}限速请在 Web UI 中设置：${NC}"
            echo -e "  ${CYAN}工具 → 选项 → 速度${NC}"
            ;;
        5)
            local port=$(grep -oP '(?<=--webui-port=)\d+' /etc/systemd/system/qbittorrent-nox.service 2>/dev/null || echo "8080")
            local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            echo -e "  ${BOLD}Web UI: ${NC}http://${server_ip}:${port}"
            echo -e "  ${BOLD}默认账户: ${NC}admin / adminadmin"
            echo -e "  ${RED}⚠ 请登录后立即修改密码${NC}"
            ;;
    esac

    sep
}

#-------------------- 功能 8：qBittorrent 服务控制 --------------------
control_qbittorrent() {
    sep
    echo -e "${BOLD}          qBittorrent 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start qbittorrent-nox; ok "已启动" ;;
        2) systemctl stop qbittorrent-nox; ok "已停止" ;;
        3) systemctl restart qbittorrent-nox; ok "已重启" ;;
        4) systemctl status qbittorrent-nox --no-pager -l ;;
    esac
    sep
}

#-------------------- 功能 9：查看 qBittorrent 状态 --------------------
show_qbittorrent_status() {
    sep
    echo -e "${BOLD}          qBittorrent 状态${NC}"
    sep
    echo ""

    if ! command -v qbittorrent-nox &>/dev/null; then
        warn "qBittorrent 未安装"
        return
    fi

    echo -e "  ${BOLD}版本：${NC}$(qbittorrent-nox --version 2>/dev/null | head -1 || echo '未知')"
    echo -e "  ${BOLD}服务：${NC}$(systemctl is-active qbittorrent-nox 2>/dev/null || echo '未运行')"

    local port=$(grep -oP '(?<=--webui-port=)\d+' /etc/systemd/system/qbittorrent-nox.service 2>/dev/null || echo "8080")
    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  ${BOLD}Web UI：${NC}http://${server_ip}:${port}"

    echo ""
    echo -e "  ${BOLD}磁盘使用：${NC}"
    df -h "$QBT_DIR" 2>/dev/null | tail -1

    sep
}

#-------------------- 功能 10：卸载 qBittorrent --------------------
uninstall_qbittorrent() {
    sep
    echo -e "${BOLD}          卸载 qBittorrent-nox${NC}"
    sep
    echo ""

    echo -n "  确认卸载？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    systemctl stop qbittorrent-nox 2>/dev/null
    systemctl disable qbittorrent-nox 2>/dev/null
    rm -f /etc/systemd/system/qbittorrent-nox.service
    systemctl daemon-reload

    apt-get remove -y qbittorrent-nox 2>/dev/null || yum remove -y qbittorrent-nox 2>/dev/null || rm -f /usr/local/bin/qbittorrent-nox
    id qbittorrent-nox &>/dev/null && userdel qbittorrent-nox 2>/dev/null

    ok "qBittorrent 已卸载"
    echo -e "  ${YELLOW}下载文件保留在 ${QBT_DIR}${NC}"

    sep
}

#=============================================================================
#                           Transmission
#=============================================================================

#-------------------- 功能 11：一键安装 Transmission --------------------
install_transmission() {
    sep
    echo -e "${BOLD}          一键安装 Transmission${NC}"
    sep
    echo ""

    info "安装 Transmission..."

    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq 2>/dev/null
            apt-get install -y transmission-daemon 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux)
            pkg_install epel-release
            pkg_install transmission-daemon 2>/dev/null || {
                # 编译安装
                install_transmission_from_source
            }
            ;;
        fedora)
            pkg_install transmission-daemon 2>/dev/null || install_transmission_from_source
            ;;
        *)
            install_transmission_from_source
            ;;
    esac

    if ! command -v transmission-daemon &>/dev/null; then
        error "Transmission 安装失败"
        return
    fi

    ok "Transmission 安装完成"

    # 先停止服务才能修改配置
    systemctl stop transmission-daemon 2>/dev/null

    # 创建下载目录
    mkdir -p "$TR_DIR"
    chown -R debian-transmission:debian-transmission "$TR_DIR" 2>/dev/null || \
    chown -R transmission:transmission "$TR_DIR" 2>/dev/null

    local conf_dir=""
    if [[ -d /etc/transmission-daemon ]]; then
        conf_dir="/etc/transmission-daemon"
    else
        conf_dir="/var/lib/transmission-daemon/info"
        mkdir -p "$conf_dir"
    fi

    local conf="${conf_dir}/settings.json"

    # Web UI 端口
    echo -n "  Web UI 端口（默认 9091）: "
    read -r webui_port
    webui_port="${webui_port:-9091}"

    # RPC 密码
    echo -n "  RPC 密码（留空自动生成）: "
    read -r rpc_pass
    if [[ -z "$rpc_pass" ]]; then
        rpc_pass=$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -1)
    fi
    local rpc_user="transmission"

    # 修改配置
    if [[ -f "$conf" ]]; then
        sed -i "s/\"download-dir\": .*/\"download-dir\": \"${TR_DIR}\",/" "$conf"
        sed -i "s/\"rpc-whitelist-enabled\": .*/\"rpc-whitelist-enabled\": false,/" "$conf"
        sed -i "s/\"rpc-port\": .*/\"rpc-port\": ${webui_port},/" "$conf"
        sed -i "s/\"rpc-username\": .*/\"rpc-username\": \"${rpc_user}\",/" "$conf"
        sed -i "s/\"rpc-password\": .*/\"rpc-password\": \"${rpc_pass}\",/" "$conf"
        sed -i "s/\"peer-port\": .*/\"peer-port\": 51413,/" "$conf"
        sed -i "s/\"encryption\": .*/\"encryption\": 1,/" "$conf"
        sed -i "s/\"dht-enabled\": .*/\"dht-enabled\": true,/" "$conf"
        sed -i "s/\"pex-enabled\": .*/\"pex-enabled\": true,/" "$conf"
        sed -i "s/\"lpd-enabled\": .*/\"lpd-enabled\": true,/" "$conf"
        sed -i "s/\"utp-enabled\": .*/\"utp-enabled\": true,/" "$conf"
    fi

    # 保存密码
    echo "${rpc_user}:${rpc_pass}" > "${conf_dir}/.rpc_auth"
    chmod 600 "${conf_dir}/.rpc_auth"

    # 启动服务
    systemctl start transmission-daemon 2>/dev/null

    # 防火墙
    open_firewall_port "$webui_port"
    open_firewall_port 51413
    open_firewall_port 51413 udp

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● Transmission 安装完成！${NC}"
    echo -e "  ${BLUE}Web UI   ：${NC}http://${server_ip}:${webui_port}"
    echo -e "  ${BLUE}用户名   ：${NC}${rpc_user}"
    echo -e "  ${BLUE}密  码   ：${NC}${MAGENTA}${rpc_pass}${NC}"
    echo -e "  ${BLUE}下载目录 ：${NC}${TR_DIR}"
    echo -e "  ${BLUE}BT 端口  ：${NC}51413"

    sep
}

# Transmission 编译安装
install_transmission_from_source() {
    warn "尝试从源码编译安装 Transmission..."

    pkg_install build-essential cmake curl libssl-dev libevent-dev libcurl4-openssl-dev zlib1g-dev 2>/dev/null || \
    pkg_install gcc cmake openssl-devel libevent-devel libcurl-devel zlib-devel 2>/dev/null

    local tr_ver="4.0.6"
    curl -L -o /tmp/transmission.tar.xz "https://github.com/transmission/transmission/releases/download/${tr_ver}/transmission-${tr_ver}.tar.xz" 2>/dev/null || \
    curl -L -o /tmp/transmission.tar.xz "https://ghp.ci/https://github.com/transmission/transmission/releases/download/${tr_ver}/transmission-${tr_ver}.tar.xz"

    cd /tmp && tar xf transmission.tar.xz 2>/dev/null
    cd "transmission-${tr_ver}" && mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DTR_DAEMON=ON -DTR_WEB=ON 2>/dev/null
    make -j$(nproc) 2>/dev/null
    make install 2>/dev/null
    cd / && rm -rf /tmp/transmission*

    # 创建 systemd 服务
    cat > /etc/systemd/system/transmission-daemon.service <<'EOF'
[Unit]
Description=Transmission BitTorrent Daemon
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/transmission-daemon -f --log-level=info
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

#-------------------- 功能 12：配置 Transmission --------------------
configure_transmission() {
    sep
    echo -e "${BOLD}          配置 Transmission${NC}"
    sep
    echo ""

    if ! command -v transmission-daemon &>/dev/null; then
        error "Transmission 未安装"
        return
    fi

    echo -e "  ${BOLD}选择配置项：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 修改下载目录"
    echo -e "  ${CYAN} 2)${NC} 修改密码"
    echo -e "  ${CYAN} 3)${NC} 修改 BT 端口"
    echo -e "  ${CYAN} 4)${NC} 查看登录信息"
    echo ""
    echo -n "请选择: "
    read -r choice

    # 找配置目录
    local conf_dir="/etc/transmission-daemon"
    [[ -d "$conf_dir" ]] || conf_dir="/var/lib/transmission-daemon/info"
    local conf="${conf_dir}/settings.json"

    # 修改配置前必须停止
    systemctl stop transmission-daemon 2>/dev/null

    case "$choice" in
        1)
            echo -n "  新下载目录: "
            read -r new_dir
            mkdir -p "$new_dir"
            sed -i "s|\"download-dir\": .*|\"download-dir\": \"${new_dir}\",|" "$conf"
            ok "下载目录已修改"
            ;;
        2)
            echo -n "  新用户名（默认 transmission）: "
            read -r new_user
            new_user="${new_user:-transmission}"
            echo -n "  新密码: "
            read -r new_pass
            sed -i "s/\"rpc-username\": .*/\"rpc-username\": \"${new_user}\",/" "$conf"
            sed -i "s/\"rpc-password\": .*/\"rpc-password\": \"${new_pass}\",/" "$conf"
            echo "${new_user}:${new_pass}" > "${conf_dir}/.rpc_auth"
            chmod 600 "${conf_dir}/.rpc_auth"
            ok "密码已修改"
            ;;
        3)
            echo -n "  BT 监听端口: "
            read -r bt_port
            sed -i "s/\"peer-port\": .*/\"peer-port\": ${bt_port},/" "$conf"
            open_firewall_port "$bt_port"
            open_firewall_port "$bt_port" udp
            ok "BT 端口已修改"
            ;;
        4)
            local rpc_port=$(grep "rpc-port" "$conf" 2>/dev/null | grep -o '[0-9]*')
            local rpc_user=$(grep "rpc-username" "$conf" 2>/dev/null | grep -o '"[^"]*"' | tail -1 | tr -d '"')
            local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            echo -e "  ${BOLD}Web UI：${NC}http://${server_ip}:${rpc_port}"
            echo -e "  ${BOLD}用户名：${NC}${rpc_user}"
            if [[ -f "${conf_dir}/.rpc_auth" ]]; then
                echo -e "  ${BOLD}密码  ：${NC}${MAGENTA}$(cat "${conf_dir}/.rpc_auth" | cut -d: -f2)${NC}"
            fi
            ;;
    esac

    systemctl start transmission-daemon 2>/dev/null

    sep
}

#-------------------- 功能 13：Transmission 服务控制 --------------------
control_transmission() {
    sep
    echo -e "${BOLD}          Transmission 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start transmission-daemon; ok "已启动" ;;
        2) systemctl stop transmission-daemon; ok "已停止" ;;
        3) systemctl restart transmission-daemon; ok "已重启" ;;
        4) systemctl status transmission-daemon --no-pager -l ;;
    esac
    sep
}

#-------------------- 功能 14：查看 Transmission 状态 --------------------
show_transmission_status() {
    sep
    echo -e "${BOLD}          Transmission 状态${NC}"
    sep
    echo ""

    if ! command -v transmission-daemon &>/dev/null; then
        warn "Transmission 未安装"
        return
    fi

    echo -e "  ${BOLD}版本：${NC}$(transmission-daemon --version 2>/dev/null | head -1 || echo '未知')"
    echo -e "  ${BOLD}服务：${NC}$(systemctl is-active transmission-daemon 2>/dev/null || echo '未运行')"

    local conf_dir="/etc/transmission-daemon"
    [[ -d "$conf_dir" ]] || conf_dir="/var/lib/transmission-daemon/info"
    local conf="${conf_dir}/settings.json"

    if [[ -f "$conf" ]]; then
        local rpc_port=$(grep "rpc-port" "$conf" | grep -o '[0-9]*')
        local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo -e "  ${BOLD}Web UI：${NC}http://${server_ip}:${rpc_port}"
    fi

    echo ""
    echo -e "  ${BOLD}磁盘使用：${NC}"
    df -h "$TR_DIR" 2>/dev/null | tail -1

    sep
}

#-------------------- 功能 15：卸载 Transmission --------------------
uninstall_transmission() {
    sep
    echo -e "${BOLD}          卸载 Transmission${NC}"
    sep
    echo ""

    echo -n "  确认卸载？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    systemctl stop transmission-daemon 2>/dev/null
    systemctl disable transmission-daemon 2>/dev/null
    rm -f /etc/systemd/system/transmission-daemon.service
    systemctl daemon-reload

    apt-get remove -y transmission-daemon 2>/dev/null || yum remove -y transmission-daemon 2>/dev/null || true
    rm -rf /usr/local/bin/transmission-daemon

    ok "Transmission 已卸载"
    echo -e "  ${YELLOW}下载文件保留在 ${TR_DIR}${NC}"

    sep
}

#=============================================================================
#                           综合管理
#=============================================================================

#-------------------- 功能 16：一键安装全部 --------------------
deploy_all() {
    sep
    echo -e "${BOLD}          一键安装全部下载软件${NC}"
    sep
    echo ""

    echo -e "  ${YELLOW}将安装：Aria2 + AriaNg / qBittorrent-nox / Transmission${NC}"
    echo -e "  ${YELLOW}注意：BT 端口 6881-6999 会被多个软件共用，可能导致冲突${NC}"
    echo -e "  ${YELLOW}建议根据需要选择安装，或分别使用不同端口${NC}"
    echo ""

    echo -n "  确认全部安装？(y/N): "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    mkdir -p "$DOWNLOAD_DIR"

    # Aria2（使用默认配置）
    echo ""
    info "=== [1/3] 安装 Aria2 ==="
    pkg_install aria2 nginx
    mkdir -p "$ARIA2_CONF_DIR" "$ARIA2_DIR"
    local rpc_secret=$(openssl rand -hex 16 2>/dev/null)

    cat > "${ARIA2_CONF_DIR}/aria2.conf" <<EOF
dir=${ARIA2_DIR}
log=${ARIA2_LOG}
log-level=warn
daemon=true
enable-rpc=true
rpc-listen-all=true
rpc-listen-port=6800
rpc-secret=${rpc_secret}
max-concurrent-downloads=5
continue=true
max-connection-per-server=16
min-split-size=10M
split=16
enable-dht=true
bt-enable-lpd=true
listen-port=6881-6999
seed-ratio=1.0
seed-time=60
disk-cache=32M
input-file=${ARIA2_SESSION}
save-session=${ARIA2_SESSION}
save-session-interval=60
EOF
    touch "$ARIA2_SESSION"

    cat > /etc/systemd/system/aria2.service <<'EOF'
[Unit]
Description=Aria2
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/bin/aria2c --conf-path=/etc/aria2/aria2.conf
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable aria2 && systemctl start aria2 2>/dev/null
    echo "$rpc_secret" > "${ARIA2_CONF_DIR}/.rpc_secret"
    chmod 600 "${ARIA2_CONF_DIR}/.rpc_secret"
    ok "Aria2 完成"

    # qBittorrent（端口 8081 避免冲突）
    echo ""
    info "=== [2/3] 安装 qBittorrent ==="
    pkg_install qbittorrent-nox 2>/dev/null || true
    if command -v qbittorrent-nox &>/dev/null; then
        mkdir -p "$QBT_DIR"
        cat > /etc/systemd/system/qbittorrent-nox.service <<'EOF'
[Unit]
Description=qBittorrent-nox
After=network-online.target
[Service]
Type=forking
ExecStart=/usr/bin/qbittorrent-nox -d --webui-port=8081
ExecStop=/usr/bin/kill -QUIT $MAINPID
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable qbittorrent-nox && systemctl start qbittorrent-nox 2>/dev/null
        ok "qBittorrent 完成（端口 8081）"
    else
        warn "qBittorrent 安装跳过"
    fi

    # Transmission（端口 9091）
    echo ""
    info "=== [3/3] 安装 Transmission ==="
    pkg_install transmission-daemon 2>/dev/null || true
    if command -v transmission-daemon &>/dev/null; then
        systemctl stop transmission-daemon 2>/dev/null
        mkdir -p "$TR_DIR"
        local tr_conf="/etc/transmission-daemon/settings.json"
        [[ -f "$tr_conf" ]] && {
            sed -i 's/"rpc-whitelist-enabled": true/"rpc-whitelist-enabled": false/' "$tr_conf"
        }
        systemctl start transmission-daemon 2>/dev/null
        ok "Transmission 完成（端口 9091）"
    else
        warn "Transmission 安装跳过"
    fi

    # AriaNg
    echo ""
    info "安装 AriaNg..."
    mkdir -p /usr/share/nginx/html/ariang
    curl -L -o /tmp/ariang.zip "https://ghp.ci/https://github.com/mayswind/AriaNg/releases/download/1.3.7/AriaNg-1.3.7.zip" 2>/dev/null
    unzip -o /tmp/ariang.zip -d /usr/share/nginx/html/ariang 2>/dev/null
    rm -f /tmp/ariang.zip

    cat > /etc/nginx/conf.d/ariang.conf <<'EOF'
server {
    listen 6801;
    location / { root /usr/share/nginx/html/ariang; index index.html; try_files $uri $uri/ /index.html; }
}
EOF
    nginx -t 2>/dev/null && systemctl enable nginx 2>/dev/null && systemctl restart nginx 2>/dev/null
    ok "AriaNg 完成"

    # 防火墙
    open_firewall_port 6800 6801 8081 9091
    open_firewall_port 6881-6999

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}${BOLD}          ● 全部下载软件安装完成！${NC}"
    echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}Aria2 + AriaNg  : ${NC}http://${server_ip}:6801  ${YELLOW}(RPC 密钥: ${rpc_secret})${NC}"
    echo -e "  ${CYAN}qBittorrent     : ${NC}http://${server_ip}:8081  ${YELLOW}(admin/adminadmin)${NC}"
    echo -e "  ${CYAN}Transmission    : ${NC}http://${server_ip}:9091  ${YELLOW}(transmission/默认密码)${NC}"

    sep
}

#-------------------- 功能 17：对比三个下载软件 --------------------
compare_tools() {
    sep
    echo -e "${BOLD}          远程下载软件对比${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}┌─────────────┬──────────────────┬──────────────────┬──────────────────┐${NC}"
    echo -e "  ${BOLD}│     特性    │     Aria2        │  qBittorrent    │  Transmission   │${NC}"
    echo -e "  ${BOLD}├─────────────┼──────────────────┼──────────────────┼──────────────────┤${NC}"
    echo -e "  │ 支持协议    │ HTTP/FTP/BT/Maglink │ BT/Maglink       │ BT/Maglink       │"
    echo -e "  │ Web UI      │ AriaNg（第三方）  │ 内置完整 UI     │ 内置简洁 UI     │"
    echo -e "  │ 多线程下载  │ 是                │ 否               │ 否               │"
    echo -e "  │ 断点续传    │ 是                │ 是               │ 是               │"
    echo -e "  │ 磁力链接    │ 是                │ 是               │ 是               │"
    echo -e "  │ 种子文件    │ 是                │ 是               │ 是               │"
    echo -e "  │ 资源占用    │ 极低（纯CLI）     │ 低               │ 极低             │"
    echo -e "  │ 下载速度    │ 极快（多线程）    │ 快               │ 一般              │"
    echo -e "  │ RSS 订阅    │ 否                │ 是               │ 是               │"
    echo -e "  │ 搜索插件    │ 否                │ 是               │ 否               │"
    echo -e "  │ 分类管理    │ 否                │ 是（标签/分类）  │ 否               │"
    echo -e "  │ 远程控制    │ RPC API          │ Web UI           │ Web UI + RPC     │"
    echo -e "  │ 开源        │ 是 (GPL)         │ 是 (GPL)         │ 是 (GPL/MIT)     │"
    echo -e "  ${BOLD}└─────────────┴──────────────────┴──────────────────┴──────────────────┘${NC}"
    echo ""

    echo -e "  ${BOLD}使用建议：${NC}"
    echo ""
    echo -e "  ${CYAN}Aria2${NC}     - ${GREEN}日常下载首选，HTTP/FTP 多线程加速，配合 AriaNg 远程管理${NC}"
    echo -e "    场景：下载大文件、磁力链接、BT 种子"
    echo ""
    echo -e "  ${CYAN}qBittorrent${NC} - ${GREEN}BT 深度用户，功能最全面，RSS/搜索/标签管理${NC}"
    echo -e "    场景：长期做种、RSS 自动下载、大量种子管理"
    echo ""
    echo -e "  ${CYAN}Transmission${NC} - ${GREEN}轻量简洁，资源占用最低${NC}"
    echo -e "    场景：低配 VPS、NAS、简单 BT 下载需求"

    sep
}

#-------------------- 主循环 --------------------
main() {
    check_root
    mkdir -p "$DOWNLOAD_DIR"

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1) install_aria2 ;;
            2) configure_aria2 ;;
            3) control_aria2 ;;
            4) show_aria2_status ;;
            5) uninstall_aria2 ;;
            6) install_qbittorrent ;;
            7) configure_qbittorrent ;;
            8) control_qbittorrent ;;
            9) show_qbittorrent_status ;;
            10) uninstall_qbittorrent ;;
            11) install_transmission ;;
            12) configure_transmission ;;
            13) control_transmission ;;
            14) show_transmission_status ;;
            15) uninstall_transmission ;;
            16) deploy_all ;;
            17) compare_tools ;;
            0|q|Q)
                echo ""
                info "退出远程下载管理脚本"
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