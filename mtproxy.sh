#!/bin/bash
#=============================================================================
# MTProto Proxy 一键部署脚本（支持 Fake TLS）
# 功能：安装/配置/启动/管理 MTProto Proxy，支持 TLS 伪装
# 支持：Docker 方式 + 二进制方式
# 用法：chmod +x mtproxy.sh && sudo ./mtproxy.sh
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
    fi
}

#-------------------- 配置路径 --------------------
CONFIG_DIR="/etc/mtproxy"
CONFIG_FILE="${CONFIG_DIR}/mtproxy.conf"
SECRET_FILE="${CONFIG_DIR}/secret"
SERVICE_FILE="/etc/systemd/system/mtproxy.service"
CONTAINER_NAME="mtproxy"

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}          MTProto Proxy 一键部署（TLS 支持）${NC}"
    sep
    echo ""

    # 显示当前状态
    local status_line=""
    if systemctl is-active --quiet mtproxy 2>/dev/null; then
        status_line="  ${BLUE}服务状态：${NC}${GREEN}运行中${NC}"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        status_line="  ${BLUE}容器状态：${NC}${GREEN}运行中（Docker）${NC}"
    else
        status_line="  ${BLUE}服务状态：${NC}${RED}未运行${NC}"
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        local current_port=$(grep "^PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        local current_domain=$(grep "^DOMAIN=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        local current_secret=$(grep "^SECRET=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        local current_type=$(grep "^TYPE=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)

        echo -e "$status_line"
        echo -e "  ${BLUE}部署方式：${NC}${CYAN}${current_type:-未知}${NC}"
        echo -e "  ${BLUE}端口    ：${NC}${CYAN}${current_port:-未知}${NC}"
        echo -e "  ${BLUE}域名    ：${NC}${CYAN}${current_domain:-未知}${NC}"
        echo -e "  ${BLUE}密钥    ：${NC}${CYAN}${current_secret:-未知}${NC}"
    else
        echo -e "$status_line"
    fi

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【部署】${NC}"
    echo -e "  ${CYAN} 1)${NC} Docker 方式一键部署（推荐）"
    echo -e "  ${CYAN} 2)${NC} 二进制方式部署（纯原生）"
    echo ""
    echo -e "  ${CYAN}【管理】${NC}"
    echo -e "  ${CYAN} 3)${NC} 查看连接信息 / 生成 Telegram 链接"
    echo -e "  ${CYAN} 4)${NC} 启动 MTProxy"
    echo -e "  ${CYAN} 5)${NC} 停止 MTProxy"
    echo -e "  ${CYAN} 6)${NC} 重启 MTProxy"
    echo -e "  ${CYAN} 7)${NC} 查看运行状态"
    echo ""
    echo -e "  ${CYAN}【配置】${NC}"
    echo -e "  ${CYAN} 8)${NC} 修改端口"
    echo -e "  ${CYAN} 9)${NC} 修改 TLS 伪装域名"
    echo -e "  ${CYAN}10)${NC} 修改密钥"
    echo -e "  ${CYAN}11)${NC} 查看配置"
    echo ""
    echo -e "  ${CYAN}【维护】${NC}"
    echo -e "  ${CYAN}12)${NC} 卸载 MTProxy"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：Docker 部署 --------------------
deploy_docker() {
    sep
    echo -e "${BOLD}          Docker 方式部署 MTProto Proxy${NC}"
    sep
    echo ""

    check_docker

    # 停止并移除旧容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "检测到旧容器，停止并移除..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        ok "旧容器已移除"
    fi

    # 读取用户输入
    read_config

    # 生成 FakeTLS secret
    info "生成 FakeTLS 密钥..."
    local raw_secret
    raw_secret=$(generate_secret)
    local tls_secret="ee${raw_secret}$(hex_encode "$DOMAIN")"

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
TYPE=docker
PORT=${PORT}
DOMAIN=${DOMAIN}
SECRET=${tls_secret}
RAW_SECRET=${raw_secret}
EOF

    # 拉取镜像
    info "拉取 MTProto Proxy 镜像..."
    docker pull ellermister/mtproxy:latest 2>/dev/null || {
        warn "拉取最新镜像失败，尝试本地镜像"
    }

    # 运行容器
    info "启动 MTProto Proxy 容器..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart=unless-stopped \
        -e domain="$DOMAIN" \
        -p "${PORT}:443" \
        ellermister/mtproxy:latest

    ok "MTProto Proxy 容器已启动"

    # 保存真正的 secret
    sleep 2
    local real_secret=$(docker logs "$CONTAINER_NAME" 2>/dev/null | grep "Secret" | head -1 | awk '{print $NF}')
    if [[ -n "$real_secret" ]]; then
        sed -i "s/^SECRET=.*/SECRET=${real_secret}/" "$CONFIG_FILE"
    fi

    print_info
}

#-------------------- 功能 2：二进制部署 --------------------
deploy_binary() {
    sep
    echo -e "${BOLD}          二进制方式部署 MTProto Proxy${NC}"
    sep
    echo ""

    # 安装依赖
    info "安装编译依赖..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID,,}" in
            ubuntu|debian|linuxmint|pop)
                apt-get update -qq
                apt-get install -y git curl wget build-essential libssl-dev 2>/dev/null
                ;;
            centos|rhel|rocky|almalinux|ol|fedora)
                local pm="yum"
                command -v dnf &>/dev/null && pm="dnf"
                $pm install -y git curl wget gcc openssl-devel 2>/dev/null
                ;;
        esac
    fi

    # 安装 Go（如果未安装）
    if ! command -v go &>/dev/null; then
        info "安装 Go 编译器..."
        local go_version="1.22.5"
        local go_arch=""
        case "$(uname -m)" in
            x86_64)  go_arch="amd64" ;;
            aarch64) go_arch="arm64" ;;
            *) go_arch="$(uname -m)" ;;
        esac

        wget -q "https://go.dev/dl/go${go_version}.linux-${go_arch}.tar.gz" -O /tmp/go.tar.gz
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm -f /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi

    # 编译 mtg
    info "克隆并编译 mtg (Go MTProto Proxy)..."
    local mtg_dir="/opt/mtg"
    rm -rf "$mtg_dir"
    git clone --depth=1 https://github.com/9seconds/mtg.git "$mtg_dir" 2>/dev/null || {
        warn "GitHub 克隆失败，尝试使用代理"
        git clone --depth=1 https://ghp.ci/https://github.com/9seconds/mtg.git "$mtg_dir" 2>/dev/null
    }

    cd "$mtg_dir"
    go build -o /usr/local/bin/mtg ./cmd/mtg/ 2>/dev/null || {
        error "编译 mtg 失败，请检查 Go 环境"
        return 1
    }

    ok "mtg 编译完成"

    # 读取用户输入
    read_config

    # 生成密钥
    local secret
    secret=$(generate_secret)
    local tls_secret="ee${secret}$(hex_encode "$DOMAIN")"

    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
TYPE=binary
PORT=${PORT}
DOMAIN=${DOMAIN}
SECRET=${tls_secret}
RAW_SECRET=${secret}
BIND=0.0.0.0
EOF

    # 生成 mtg 配置文件
    cat > "${CONFIG_DIR}/mtg.toml" <<EOF
# mtg configuration file
# See: https://github.com/9seconds/mtg

secret = "${tls_secret}"
bind-to = "0.0.0.0:${PORT}"

[network]
prefer-ip = "prefer-ipv4"
EOF

    # 创建 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTProto Proxy Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/mtg run ${CONFIG_DIR}/mtg.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mtproxy
    systemctl start mtproxy

    ok "MTProto Proxy 服务已启动"

    print_info
}

#-------------------- 读取配置 --------------------
read_config() {
    echo ""
    echo -e "  ${YELLOW}提示：FakeTLS 使用伪装域名模拟 HTTPS 流量，可有效绕过 DPI 检测${NC}"
    echo ""

    # 端口
    echo -n "  输入监听端口（默认 443）: "
    read -r PORT
    PORT="${PORT:-443}"

    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
        error "无效端口号"
    fi

    # TLS 域名
    echo ""
    echo -e "  ${BOLD}选择 TLS 伪装域名：${NC}"
    echo -e "  ${CYAN} 1)${NC} google.com          ${GREEN}（推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} cloudflare.com"
    echo -e "  ${CYAN} 3)${NC} apple.com"
    echo -e "  ${CYAN} 4)${NC} github.com"
    echo -e "  ${CYAN} 5)${NC} 自定义域名"
    echo ""
    echo -n "  请选择 [1-5]（默认 1）: "
    read -r domain_choice

    case "$domain_choice" in
        2) DOMAIN="cloudflare.com" ;;
        3) DOMAIN="apple.com" ;;
        4) DOMAIN="github.com" ;;
        5)
            echo -n "  输入伪装域名: "
            read -r DOMAIN
            ;;
        *) DOMAIN="google.com" ;;
    esac

    # 防火墙放行
    echo ""
    info "配置防火墙..."
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${PORT}/tcp" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        ok "firewalld 已开放端口 ${PORT}"
    fi

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "${PORT}/tcp" 2>/dev/null
        ok "UFW 已开放端口 ${PORT}"
    fi
}

#-------------------- 生成密钥 --------------------
#-------------------- 域名转十六进制（兼容无 xxd 环境）--------------------
hex_encode() {
    if command -v xxd &>/dev/null; then
        printf '%s' "$1" | xxd -p -c 256
    else
        local s="$1"
        local result=""
        for (( i=0; i<${#s}; i++ )); do
            local c="${s:$i:1}"
            local hex
            hex=$(printf '%02x' "'$c")
            result+="$hex"
        done
        printf '%s' "$result"
    fi
}

#-------------------- 生成密钥 --------------------
generate_secret() {
    openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -1
}

#-------------------- 显示连接信息 --------------------
print_info() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "未找到配置文件"
        return
    fi

    source "$CONFIG_FILE"

    local server_ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "获取失败")

    sep
    echo -e "${BOLD}                    MTProto Proxy 连接信息${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}服务器 IP：${NC}${CYAN}${server_ip}${NC}"
    echo -e "  ${BLUE}端口    ：${NC}${CYAN}${PORT}${NC}"
    echo -e "  ${BLUE}密钥    ：${NC}${MAGENTA}${SECRET}${NC}"
    echo -e "  ${BLUE}TLS 域名：${NC}${CYAN}${DOMAIN}${NC}"

    echo ""

    echo -e "  ${GREEN}${BOLD}Telegram 代理链接：${NC}"
    echo ""
    echo -e "  ${CYAN}https://t.me/proxy?server=${server_ip}&port=${PORT}&secret=${SECRET}${NC}"
    echo ""

    echo -e "  ${GREEN}${BOLD}手动配置参数：${NC}"
    echo -e "    协议类型 : ${CYAN}MTProto${NC}"
    echo -e "    服务器   : ${CYAN}${server_ip}${NC}"
    echo -e "    端口     : ${CYAN}${PORT}${NC}"
    echo -e "    密钥     : ${MAGENTA}${SECRET}${NC}"

    echo ""

    echo -e "  ${YELLOW}提示：在 Telegram 客户端中${NC}"
    echo -e "  ${YELLOW}点击 设置 → 数据和存储 → 代理设置 → 添加代理${NC}"
    echo -e "  ${YELLOW}选择 MTProto，填入上述参数即可${NC}"

    echo ""

    # 生成二维码
    if command -v qrencode &>/dev/null; then
        local tg_link="https://t.me/proxy?server=${server_ip}&port=${PORT}&secret=${SECRET}"
        echo -e "  ${GREEN}${BOLD}Telegram 代理链接（可复制）${NC}"
        echo ""
        echo -e "    ${CYAN}${tg_link}${NC}"
        echo ""
    fi

    sep
}

#-------------------- 检查 Docker --------------------
check_docker() {
    if ! command -v docker &>/dev/null; then
        info "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        systemctl enable docker
        systemctl start docker
        ok "Docker 安装完成"
    else
        ok "Docker 已安装"
    fi
}

#-------------------- 功能 3：查看连接信息 --------------------
show_info() {
    print_info
}

#-------------------- 功能 4/5/6：启动/停止/重启 --------------------
start_proxy() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "未找到配置文件，请先部署 MTProxy"
        return
    fi

    source "$CONFIG_FILE"

    if [[ "$TYPE" == "docker" ]]; then
        docker start "$CONTAINER_NAME" 2>/dev/null || {
            docker run -d --name "$CONTAINER_NAME" --restart=unless-stopped \
                -e domain="$DOMAIN" -p "${PORT}:443" ellermister/mtproxy:latest
        }
    else
        systemctl start mtproxy
    fi

    ok "MTProto Proxy 已启动"
}

stop_proxy() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "未找到配置文件"
        return
    fi

    source "$CONFIG_FILE"

    if [[ "$TYPE" == "docker" ]]; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
    else
        systemctl stop mtproxy 2>/dev/null || true
    fi

    ok "MTProto Proxy 已停止"
}

restart_proxy() {
    stop_proxy
    sleep 1
    start_proxy
}

#-------------------- 功能 7：查看运行状态 --------------------
show_status() {
    sep
    echo -e "${BOLD}              MTProto Proxy 运行状态${NC}"
    sep
    echo ""

    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "未找到配置文件"
        sep
        return
    fi

    source "$CONFIG_FILE"

    if [[ "$TYPE" == "docker" ]]; then
        echo -e "  ${BOLD}容器状态：${NC}"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        echo ""
        echo -e "  ${BOLD}容器日志（最近 20 行）：${NC}"
        echo ""
        docker logs --tail 20 "$CONTAINER_NAME" 2>/dev/null || warn "无法获取日志"
    else
        echo -e "  ${BOLD}服务状态：${NC}"
        echo ""
        systemctl status mtproxy --no-pager 2>/dev/null || warn "服务未运行"
        echo ""
        echo -e "  ${BOLD}服务日志（最近 20 行）：${NC}"
        echo ""
        journalctl -u mtproxy --no-pager -n 20 2>/dev/null || warn "无法获取日志"
    fi

    sep
}

#-------------------- 功能 8：修改端口 --------------------
change_port() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "未找到配置文件"
        return
    fi

    source "$CONFIG_FILE"

    echo -n "  输入新端口（当前 ${PORT}）: "
    read -r new_port

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        error "无效端口号"
        return
    fi

    # 更新配置
    sed -i "s/^PORT=.*/PORT=${new_port}/" "$CONFIG_FILE"

    # 防火墙更新
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --remove-port="${PORT}/tcp" 2>/dev/null || true
        firewall-cmd --permanent --add-port="${new_port}/tcp" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw delete allow "${PORT}/tcp" 2>/dev/null || true
        ufw allow "${new_port}/tcp" 2>/dev/null
    fi

    ok "端口已修改为 ${new_port}"

    # 重启服务
    warn "需要重启服务以生效"
    restart_proxy

    print_info
}

#-------------------- 功能 9：修改 TLS 域名 --------------------
change_domain() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "未找到配置文件"
        return
    fi

    source "$CONFIG_FILE"

    echo -n "  输入新伪装域名（当前 ${DOMAIN}）: "
    read -r new_domain

    if [[ -z "$new_domain" ]]; then
        warn "域名不能为空"
        return
    fi

    # 重新生成密钥
    local new_secret="ee${RAW_SECRET}$(hex_encode "$new_domain")"

    sed -i "s/^DOMAIN=.*/DOMAIN=${new_domain}/" "$CONFIG_FILE"
    sed -i "s/^SECRET=.*/SECRET=${new_secret}/" "$CONFIG_FILE"

    ok "TLS 域名已修改为 ${new_domain}"

    # 重启服务
    warn "需要重启服务以生效"
    restart_proxy

    print_info
}

#-------------------- 功能 10：修改密钥 --------------------
change_secret() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "未找到配置文件"
        return
    fi

    source "$CONFIG_FILE"

    echo -n "  输入新密钥（留空则自动生成）: "
    read -r new_secret

    if [[ -z "$new_secret" ]]; then
        new_secret=$(generate_secret)
    fi

    local tls_secret="ee${new_secret}$(hex_encode "$DOMAIN")"

    sed -i "s/^RAW_SECRET=.*/RAW_SECRET=${new_secret}/" "$CONFIG_FILE"
    sed -i "s/^SECRET=.*/SECRET=${tls_secret}/" "$CONFIG_FILE"

    ok "密钥已更新"

    # 重启服务
    warn "需要重启服务以生效"
    restart_proxy

    print_info
}

#-------------------- 功能 11：查看配置 --------------------
show_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "未找到配置文件"
        return
    fi

    sep
    echo -e "${BOLD}              当前配置${NC}"
    sep
    echo ""
    cat "$CONFIG_FILE" | while read -r line; do
        if echo "$line" | grep -q "^SECRET="; then
            local val=$(echo "$line" | cut -d= -f2-)
            echo -e "  ${CYAN}SECRET = ${MAGENTA}${val}${NC}"
        else
            echo -e "  ${CYAN}${line}${NC}"
        fi
    done
    sep
}

#-------------------- 功能 12：卸载 --------------------
uninstall() {
    sep
    echo -e "${BOLD}              卸载 MTProto Proxy${NC}"
    sep
    echo ""

    warn "此操作将删除 MTProto Proxy 及其所有配置！"
    echo -n "  确认卸载？输入 YES: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    # 停止服务/容器
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    systemctl stop mtproxy 2>/dev/null || true
    systemctl disable mtproxy 2>/dev/null || true

    # 清理文件
    rm -f "$SERVICE_FILE"
    rm -rf "$CONFIG_DIR"
    rm -f /usr/local/bin/mtg
    rm -rf /opt/mtg

    systemctl daemon-reload

    ok "MTProto Proxy 已卸载"
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
            1)  deploy_docker ;;
            2)  deploy_binary ;;
            3)  show_info ;;
            4)  start_proxy ;;
            5)  stop_proxy ;;
            6)  restart_proxy ;;
            7)  show_status ;;
            8)  change_port ;;
            9)  change_domain ;;
            10) change_secret ;;
            11) show_config ;;
            12) uninstall ;;
            0|q|Q)
                echo ""
                info "退出 MTProto Proxy 管理脚本"
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
