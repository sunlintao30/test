#!/bin/bash
#=============================================================================
# EasyTier 组网管理脚本（服务端 / 客户端 / Docker 支持）
# 功能：支持服务端部署、客户端连接、Docker/原生双模式、IP分配配置
# 用法：chmod +x easytier_manager.sh && sudo ./easytier_manager.sh
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

#-------------------- 路径定义 --------------------
CONFIG_DIR="/etc/easytier"
ET_BIN="/usr/local/bin/easytier-core"
ET_CLI="/usr/local/bin/easytier-cli"
CONTAINER_NAME="easytier"

#-------------------- 检测安装状态 --------------------
is_installed() {
    command -v easytier-core &>/dev/null || [[ -f "$ET_BIN" ]]
}

is_docker_installed() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"
}

#-------------------- 主菜单 --------------------
show_main_menu() {
    clear
    sep
    echo -e "${BOLD}          EasyTier 组网管理脚本${NC}"
    sep
    echo ""

    local et_status="${RED}未安装${NC}"
    if is_installed; then
        if systemctl is-active --quiet easytier 2>/dev/null; then
            et_status="${GREEN}运行中（原生）${NC}"
        else
            et_status="${YELLOW}已安装（未运行）${NC}"
        fi
    elif is_docker_installed; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
            et_status="${GREEN}运行中（Docker）${NC}"
        else
            et_status="${YELLOW}已安装 Docker 版（未运行）${NC}"
        fi
    fi

    echo -e "  ${BLUE}当前状态：${NC}${et_status}"
    echo ""
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 服务端模式"
    echo -e "  ${CYAN} 2)${NC} 客户端模式"
    echo -e "  ${CYAN} 3)${NC} 安装 EasyTier（仅安装二进制）"
    echo -e "  ${CYAN} 4)${NC} 卸载 EasyTier"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 服务端子菜单 --------------------
show_server_menu() {
    clear
    sep
    echo -e "${BOLD}          EasyTier - 服务端模式${NC}"
    sep
    echo ""

    local svc_status="${RED}未运行${NC}"
    if systemctl is-active --quiet easytier 2>/dev/null; then
        svc_status="${GREEN}运行中（原生）${NC}"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        svc_status="${GREEN}运行中（Docker）${NC}"
    fi

    echo -e "  ${BLUE}服务状态：${NC}${svc_status}"

    if [[ -f "${CONFIG_DIR}/server.toml" ]]; then
        local net_name=$(grep "network_name" "${CONFIG_DIR}/server.toml" 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d '"')
        local listen_port=$(grep "listeners" "${CONFIG_DIR}/server.toml" 2>/dev/null | head -1 | sed 's/.*://g' | tr -d '"')
        local ipv4=$(grep "ipv4" "${CONFIG_DIR}/server.toml" 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d '"')
        echo -e "  ${BLUE}网络名称：${NC}${CYAN}${net_name}${NC}"
        echo -e "  ${BLUE}监听端口：${NC}${CYAN}${listen_port}${NC}"
        echo -e "  ${BLUE}虚拟 IP ：${NC}${CYAN}${ipv4}${NC}"
    fi

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【部署】${NC}"
    echo -e "  ${CYAN} 1)${NC} 原生安装（systemd 服务）"
    echo -e "  ${CYAN} 2)${NC} Docker 安装"
    echo ""
    echo -e "  ${CYAN}【管理】${NC}"
    echo -e "  ${CYAN} 3)${NC} 查看连接节点"
    echo -e "  ${CYAN} 4)${NC} 查看网络拓扑"
    echo -e "  ${CYAN} 5)${NC} 启动服务"
    echo -e "  ${CYAN} 6)${NC} 停止服务"
    echo -e "  ${CYAN} 7)${NC} 重启服务"
    echo ""
    echo -e "  ${CYAN}【配置】${NC}"
    echo -e "  ${CYAN} 8)${NC} 修改网络名称 / 密码"
    echo -e "  ${CYAN} 9)${NC} 修改监听端口"
    echo -e "  ${CYAN}10)${NC} 修改虚拟 IP / DHCP 分配"
    echo -e "  ${CYAN}11)${NC} 子网代理配置"
    echo -e "  ${CYAN}12)${NC} 高级选项（RPC/加密/P2P等）"
    echo -e "  ${CYAN}13)${NC} 查看当前配置"
    echo ""
    echo -e "  ${CYAN} 0)${NC} 返回主菜单"
    sep
    echo -n "请输入选项: "
}

#-------------------- 客户端子菜单 --------------------
show_client_menu() {
    clear
    sep
    echo -e "${BOLD}          EasyTier - 客户端模式${NC}"
    sep
    echo ""

    local svc_status="${RED}未运行${NC}"
    if systemctl is-active --quiet easytier 2>/dev/null; then
        svc_status="${GREEN}运行中（原生）${NC}"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        svc_status="${GREEN}运行中（Docker）${NC}"
    fi

    echo -e "  ${BLUE}服务状态：${NC}${svc_status}"

    if [[ -f "${CONFIG_DIR}/client.toml" ]]; then
        local net_name=$(grep "network_name" "${CONFIG_DIR}/client.toml" 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d '"')
        local peers=$(grep "peers" "${CONFIG_DIR}/client.toml" 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d '"')
        local ipv4=$(grep "ipv4" "${CONFIG_DIR}/client.toml" 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d '"')
        echo -e "  ${BLUE}网络名称：${NC}${CYAN}${net_name}${NC}"
        echo -e "  ${BLUE}服务端  ：${NC}${CYAN}${peers}${NC}"
        echo -e "  ${BLUE}虚拟 IP ：${NC}${CYAN}${ipv4}${NC}"
    fi

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【部署】${NC}"
    echo -e "  ${CYAN} 1)${NC} 原生安装（systemd 服务）"
    echo -e "  ${CYAN} 2)${NC} Docker 安装"
    echo ""
    echo -e "  ${CYAN}【管理】${NC}"
    echo -e "  ${CYAN} 3)${NC} 查看连接状态"
    echo -e "  ${CYAN} 4)${NC} 查看路由表"
    echo -e "  ${CYAN} 5)${NC} 启动服务"
    echo -e "  ${CYAN} 6)${NC} 停止服务"
    echo -e "  ${CYAN} 7)${NC} 重启服务"
    echo ""
    echo -e "  ${CYAN}【配置】${NC}"
    echo -e "  ${CYAN} 8)${NC} 修改服务端地址"
    echo -e "  ${CYAN} 9)${NC} 修改网络名称 / 密码"
    echo -e "  ${CYAN}10)${NC} 修改虚拟 IP（固定/DHCP）"
    echo -e "  ${CYAN}11)${NC} 子网代理配置"
    echo -e "  ${CYAN}12)${NC} 高级选项（加密/出口节点/SOCKS5等）"
    echo -e "  ${CYAN}13)${NC} 查看当前配置"
    echo ""
    echo -e "  ${CYAN} 0)${NC} 返回主菜单"
    sep
    echo -n "请输入选项: "
}

#=============================================================================
# 公共函数
#=============================================================================

install_easytier() {
    if is_installed; then
        ok "EasyTier 已安装: $(easytier-core --version 2>/dev/null | head -1 || echo 'unknown')"
        return
    fi

    info "安装 EasyTier..."

    local arch=$(uname -m)
    local et_arch=""
    case "$arch" in
        x86_64)  et_arch="x86_64" ;;
        aarch64) et_arch="aarch64" ;;
        armv7l)  et_arch="armv7" ;;
        *)       et_arch="x86_64" ;;
    esac

    local latest=$(curl -s https://api.github.com/repos/EasyTier/EasyTier/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    local url="https://github.com/EasyTier/EasyTier/releases/download/${latest}/easytier-linux-${et_arch}.zip"

    info "下载 EasyTier ${latest} (${et_arch})..."
    curl -fsSL "$url" -o /tmp/easytier.zip 2>/dev/null || {
        warn "GitHub 下载失败，尝试备用代理..."
        curl -fsSL "https://ghp.ci/$url" -o /tmp/easytier.zip
    }

    unzip -o /tmp/easytier.zip -d /tmp/easytier/ 2>/dev/null
    cp /tmp/easytier/easytier-core "$ET_BIN"
    cp /tmp/easytier/easytier-cli "$ET_CLI"
    chmod +x "$ET_BIN" "$ET_CLI"
    rm -rf /tmp/easytier /tmp/easytier.zip

    ok "EasyTier 安装完成"
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        info "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        systemctl enable docker
        systemctl start docker
        ok "Docker 安装完成"
    fi
}

open_firewall() {
    local port=$1
    info "配置防火墙..."
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null || true
        firewall-cmd --permanent --add-port="${port}/udp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null
        ok "firewalld 已开放端口 ${port}"
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "${port}/tcp" 2>/dev/null || true
        ufw allow "${port}/udp" 2>/dev/null || true
        ok "UFW 已开放端口 ${port}"
    fi
}

#=============================================================================
# 服务端函数
#=============================================================================

server_native_install() {
    sep
    echo -e "${BOLD}          EasyTier 服务端 - 原生安装${NC}"
    sep
    echo ""

    install_easytier

    # 交互式配置
    local config
    config=$(server_config_wizard)

    mkdir -p "$CONFIG_DIR"
    echo "$config" > "${CONFIG_DIR}/server.toml"

    # 提取端口放行防火墙
    local listen_port=$(echo "$config" | grep "listeners" | head -1 | sed 's/.*://g' | tr -d '"' | tr -d ']' | tr -d '[')
    open_firewall "$listen_port"

    # 创建 systemd 服务
    cat > /etc/systemd/system/easytier.service <<EOF
[Unit]
Description=EasyTier Network Service
After=network.target

[Service]
Type=simple
ExecStart=${ET_BIN} -c ${CONFIG_DIR}/server.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable easytier
    systemctl restart easytier

    ok "EasyTier 服务端已启动"
    echo ""
    server_print_info
}

server_docker_install() {
    sep
    echo -e "${BOLD}          EasyTier 服务端 - Docker 安装${NC}"
    sep
    echo ""

    check_docker
    install_easytier

    # 停止并移除旧容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi

    # 交互式配置
    local config
    config=$(server_config_wizard)

    mkdir -p "$CONFIG_DIR"
    echo "$config" > "${CONFIG_DIR}/server.toml"

    # 提取端口
    local listen_port=$(echo "$config" | grep "listeners" | head -1 | sed 's/.*://g' | tr -d '"' | tr -d ']' | tr -d '[')
    open_firewall "$listen_port"

    # 运行容器
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart=unless-stopped \
        --privileged \
        --network host \
        -v "${CONFIG_DIR}/server.toml:/app/server.toml" \
        -e TZ=Asia/Shanghai \
        easytier/easytier:latest \
        -c /app/server.toml

    ok "EasyTier 服务端 Docker 容器已启动"
    echo ""
    server_print_info
}

server_config_wizard() {
    echo ""
    echo -e "  ${BOLD}服务端配置向导${NC}"
    echo ""

    # 网络名称
    echo -n "  网络名称（如 my-vpn）: "
    read -r net_name
    net_name="${net_name:-easytier-net}"

    # 网络密码
    local net_secret=$(openssl rand -base64 24 2>/dev/null | tr -d '=+/')
    echo -n "  网络密码（留空则自动生成）: "
    read -r input_secret
    net_secret="${input_secret:-$net_secret}"

    # 监听端口
    echo ""
    echo -n "  监听端口（默认 11010）: "
    read -r listen_port
    listen_port="${listen_port:-11010}"

    # 虚拟 IP
    echo ""
    echo -e "  ${BOLD}虚拟 IP 配置${NC}"
    echo -e "  ${CYAN} 1)${NC} 指定固定 IP（推荐服务端使用）"
    echo -e "  ${CYAN} 2)${NC} DHCP 自动分配"
    echo ""
    echo -n "  请选择 [1/2]（默认 1）: "
    read -r ip_choice

    local ip_config=""
    if [[ "$ip_choice" == "2" ]]; then
        ip_config="dhcp = true"
    else
        echo -n "  输入固定 IP（如 10.144.144.1）: "
        read -r fixed_ip
        fixed_ip="${fixed_ip:-10.144.144.1}"
        ip_config="ipv4 = \"${fixed_ip}\""
    fi

    # 子网代理
    echo ""
    echo -n "  是否启用子网代理？(y/N): "
    read -r proxy_choice
    local proxy_config=""
    if [[ "$proxy_choice" =~ ^[Yy]$ ]]; then
        echo -n "  输入要代理的子网（如 192.168.1.0/24）: "
        read -r proxy_net
        proxy_config="proxy_networks = [\"${proxy_net}\"]"
    fi

    # RPC 端口
    echo ""
    echo -n "  RPC 管理端口（默认 15888，0 表示随机）: "
    read -r rpc_port
    rpc_port="${rpc_port:-15888}"

    # 高级选项
    echo ""
    echo -n "  是否启用安全模式（secure mode）？(y/N): "
    read -r secure_choice
    local secure_config=""
    [[ "$secure_choice" =~ ^[Yy]$ ]] && secure_config="secure_mode = true"

    echo -n "  是否启用出口节点（其他节点可通过本节点上网）？(y/N): "
    read -r exit_choice
    local exit_config=""
    [[ "$exit_choice" =~ ^[Yy]$ ]] && exit_config="enable_exit_node = true"

    echo -n "  是否启用魔法 DNS（hostname.et.net）？(y/N): "
    read -r dns_choice
    local dns_config=""
    [[ "$dns_choice" =~ ^[Yy]$ ]] && dns_config="accept_dns = true"

    # 生成 TOML
    cat <<EOF
# EasyTier 服务端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

network_name = "${net_name}"
network_secret = "${net_secret}"

${ip_config}

listeners = ["tcp://0.0.0.0:${listen_port}", "udp://0.0.0.0:${listen_port}"]
rpc_portal = "0.0.0.0:${rpc_port}"

hostname = "$(hostname)"

${proxy_config}
${secure_config}
${exit_config}
${dns_config}

# 默认允许 P2P 和转发
# private_mode = false
EOF
}

server_print_info() {
    if [[ ! -f "${CONFIG_DIR}/server.toml" ]]; then
        warn "未找到服务端配置"
        return
    fi

    local server_ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
    local net_name=$(grep "network_name" "${CONFIG_DIR}/server.toml" | head -1 | sed 's/.*= *//' | tr -d '"')
    local net_secret=$(grep "network_secret" "${CONFIG_DIR}/server.toml" | head -1 | sed 's/.*= *//' | tr -d '"')
    local listen_port=$(grep "listeners" "${CONFIG_DIR}/server.toml" | head -1 | sed 's/.*://g' | tr -d '"' | tr -d ']' | tr -d '[')
    local ipv4=$(grep "^ipv4" "${CONFIG_DIR}/server.toml" | head -1 | sed 's/.*= *//' | tr -d '"')
    local dhcp=$(grep "^dhcp" "${CONFIG_DIR}/server.toml" | head -1 | sed 's/.*= *//')

    sep
    echo -e "${BOLD}                    EasyTier 服务端信息${NC}"
    sep
    echo ""
    echo -e "  ${BLUE}公网 IP ：${NC}${CYAN}${server_ip}${NC}"
    echo -e "  ${BLUE}监听端口：${NC}${CYAN}${listen_port}${NC}"
    echo -e "  ${BLUE}网络名称：${NC}${CYAN}${net_name}${NC}"
    echo -e "  ${BLUE}网络密码：${NC}${MAGENTA}${net_secret}${NC}"
    if [[ -n "$ipv4" ]]; then
        echo -e "  ${BLUE}虚拟 IP ：${NC}${CYAN}${ipv4}${NC}"
    elif [[ "$dhcp" == "true" ]]; then
        echo -e "  ${BLUE}虚拟 IP ：${NC}${CYAN}DHCP 自动分配${NC}"
    fi
    echo ""
    echo -e "  ${GREEN}${BOLD}客户端连接命令：${NC}"
    echo ""
    echo -e "  ${CYAN}easytier-core -d --network-name ${net_name} --network-secret ${net_secret} -p tcp://${server_ip}:${listen_port}${NC}"
    echo ""
    echo -e "  ${YELLOW}提示：客户端需要相同的 network_name 和 network_secret${NC}"
    sep
}

server_list_peers() {
    sep
    echo -e "${BOLD}              已连接节点${NC}"
    sep
    echo ""

    if is_docker_installed; then
        docker exec "$CONTAINER_NAME" easytier-cli peer 2>/dev/null || warn "无法获取节点列表"
    elif is_installed; then
        easytier-cli peer 2>/dev/null || warn "无法获取节点列表（服务可能未运行）"
    else
        warn "EasyTier 未安装"
    fi

    sep
}

server_route_list() {
    sep
    echo -e "${BOLD}              网络路由表${NC}"
    sep
    echo ""

    if is_docker_installed; then
        docker exec "$CONTAINER_NAME" easytier-cli route 2>/dev/null || warn "无法获取路由表"
    elif is_installed; then
        easytier-cli route 2>/dev/null || warn "无法获取路由表"
    else
        warn "EasyTier 未安装"
    fi

    sep
}

server_modify_config() {
    if [[ ! -f "${CONFIG_DIR}/server.toml" ]]; then
        error "未找到服务端配置"
        return
    fi

    sep
    echo -e "${BOLD}              修改服务端配置${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 修改网络名称 / 密码"
    echo -e "  ${CYAN} 2)${NC} 修改监听端口"
    echo -e "  ${CYAN} 3)${NC} 修改虚拟 IP / DHCP"
    echo -e "  ${CYAN} 4)${NC} 子网代理配置"
    echo -e "  ${CYAN} 5)${NC} 高级选项"
    echo -e "  ${CYAN} 6)${NC} 使用编辑器修改配置文件"
    echo ""
    echo -n "请选择: "
    read -r mod_choice

    case "$mod_choice" in
        1)
            echo -n "  新网络名称: "
            read -r new_name
            echo -n "  新网络密码: "
            read -r new_secret
            [[ -n "$new_name" ]] && sed -i "s/network_name = .*/network_name = \"${new_name}\"/" "${CONFIG_DIR}/server.toml"
            [[ -n "$new_secret" ]] && sed -i "s/network_secret = .*/network_secret = \"${new_secret}\"/" "${CONFIG_DIR}/server.toml"
            ok "网络名称/密码已更新"
            ;;
        2)
            echo -n "  新监听端口: "
            read -r new_port
            if [[ -n "$new_port" ]]; then
                sed -i "s|tcp://0.0.0.0:[0-9]*|tcp://0.0.0.0:${new_port}|g" "${CONFIG_DIR}/server.toml"
                sed -i "s|udp://0.0.0.0:[0-9]*|udp://0.0.0.0:${new_port}|g" "${CONFIG_DIR}/server.toml"
                open_firewall "$new_port"
                ok "监听端口已更新为 ${new_port}"
            fi
            ;;
        3)
            echo -e "  ${CYAN} 1)${NC} 指定固定 IP"
            echo -e "  ${CYAN} 2)${NC} DHCP 自动分配"
            echo -n "  请选择: "
            read -r ip_choice
            if [[ "$ip_choice" == "2" ]]; then
                sed -i '/^ipv4 = /d' "${CONFIG_DIR}/server.toml"
                grep -q "^dhcp = true" "${CONFIG_DIR}/server.toml" || echo "dhcp = true" >> "${CONFIG_DIR}/server.toml"
                ok "已切换到 DHCP 自动分配"
            else
                echo -n "  输入固定 IP: "
                read -r new_ip
                sed -i '/^dhcp = /d' "${CONFIG_DIR}/server.toml"
                if grep -q "^ipv4 = " "${CONFIG_DIR}/server.toml"; then
                    sed -i "s|ipv4 = .*|ipv4 = \"${new_ip}\"|" "${CONFIG_DIR}/server.toml"
                else
                    echo "ipv4 = \"${new_ip}\"" >> "${CONFIG_DIR}/server.toml"
                fi
                ok "虚拟 IP 已更新为 ${new_ip}"
            fi
            ;;
        4)
            echo -n "  输入子网（如 192.168.1.0/24，空则删除）: "
            read -r new_proxy
            sed -i '/proxy_networks/d' "${CONFIG_DIR}/server.toml"
            if [[ -n "$new_proxy" ]]; then
                echo "proxy_networks = [\"${new_proxy}\"]" >> "${CONFIG_DIR}/server.toml"
                ok "子网代理已更新"
            else
                ok "子网代理已删除"
            fi
            ;;
        5)
            server_advanced_config
            return
            ;;
        6)
            local editor=""
            for ed in nano vim vi; do
                command -v "$ed" &>/dev/null && { editor="$ed"; break; }
            done
            [[ -n "$editor" ]] && "$editor" "${CONFIG_DIR}/server.toml"
            ;;
    esac

    echo ""
    echo -n "  是否重启服务以生效？(Y/n): "
    read -r restart
    if [[ ! "$restart" =~ ^[Nn]$ ]]; then
        restart_service
    fi
}

server_advanced_config() {
    echo ""
    echo -e "  ${BOLD}高级选项配置${NC}"
    echo ""
    echo -n "  RPC 管理端口（当前: $(grep rpc_portal "${CONFIG_DIR}/server.toml" | sed 's/.*://g' | tr -d '"')）: "
    read -r new_rpc
    [[ -n "$new_rpc" ]] && sed -i "s|rpc_portal = .*|rpc_portal = \"0.0.0.0:${new_rpc}\"|" "${CONFIG_DIR}/server.toml"

    echo -n "  启用安全模式？(y/N): "
    read -r secure
    if [[ "$secure" =~ ^[Yy]$ ]]; then
        grep -q "secure_mode" "${CONFIG_DIR}/server.toml" && sed -i 's/secure_mode = .*/secure_mode = true/' "${CONFIG_DIR}/server.toml" || echo "secure_mode = true" >> "${CONFIG_DIR}/server.toml"
    fi

    echo -n "  启用出口节点？(y/N): "
    read -r exit_node
    if [[ "$exit_node" =~ ^[Yy]$ ]]; then
        grep -q "enable_exit_node" "${CONFIG_DIR}/server.toml" && sed -i 's/enable_exit_node = .*/enable_exit_node = true/' "${CONFIG_DIR}/server.toml" || echo "enable_exit_node = true" >> "${CONFIG_DIR}/server.toml"
    fi

    echo -n "  启用魔法 DNS？(y/N): "
    read -r magic_dns
    if [[ "$magic_dns" =~ ^[Yy]$ ]]; then
        grep -q "accept_dns" "${CONFIG_DIR}/server.toml" && sed -i 's/accept_dns = .*/accept_dns = true/' "${CONFIG_DIR}/server.toml" || echo "accept_dns = true" >> "${CONFIG_DIR}/server.toml"
    fi

    echo -n "  启用私有模式（仅同网络节点可连接）？(y/N): "
    read -r private
    if [[ "$private" =~ ^[Yy]$ ]]; then
        grep -q "private_mode" "${CONFIG_DIR}/server.toml" && sed -i 's/private_mode = .*/private_mode = true/' "${CONFIG_DIR}/server.toml" || echo "private_mode = true" >> "${CONFIG_DIR}/server.toml"
    fi

    ok "高级选项已更新"
}

server_show_config() {
    if [[ -f "${CONFIG_DIR}/server.toml" ]]; then
        sep
        echo -e "${BOLD}              服务端配置${NC}"
        sep
        echo ""
        cat "${CONFIG_DIR}/server.toml"
        sep
    else
        warn "未找到服务端配置"
    fi
}

#=============================================================================
# 客户端函数
#=============================================================================

client_native_install() {
    sep
    echo -e "${BOLD}          EasyTier 客户端 - 原生安装${NC}"
    sep
    echo ""

    install_easytier

    local config
    config=$(client_config_wizard)

    mkdir -p "$CONFIG_DIR"
    echo "$config" > "${CONFIG_DIR}/client.toml"

    cat > /etc/systemd/system/easytier.service <<EOF
[Unit]
Description=EasyTier Client Service
After=network.target

[Service]
Type=simple
ExecStart=${ET_BIN} -c ${CONFIG_DIR}/client.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable easytier
    systemctl restart easytier

    ok "EasyTier 客户端已启动"
}

client_docker_install() {
    sep
    echo -e "${BOLD}          EasyTier 客户端 - Docker 安装${NC}"
    sep
    echo ""

    check_docker
    install_easytier

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi

    local config
    config=$(client_config_wizard)

    mkdir -p "$CONFIG_DIR"
    echo "$config" > "${CONFIG_DIR}/client.toml"

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart=unless-stopped \
        --privileged \
        --network host \
        -v "${CONFIG_DIR}/client.toml:/app/client.toml" \
        -e TZ=Asia/Shanghai \
        easytier/easytier:latest \
        -c /app/client.toml

    ok "EasyTier 客户端 Docker 容器已启动"
}

client_config_wizard() {
    echo ""
    echo -e "  ${BOLD}客户端配置向导${NC}"
    echo ""

    echo -n "  服务端地址（如 1.2.3.4:11010）: "
    read -r server_addr
    server_addr="${server_addr:-127.0.0.1:11010}"

    echo -n "  网络名称: "
    read -r net_name
    net_name="${net_name:-easytier-net}"

    echo -n "  网络密码: "
    read -r net_secret

    echo ""
    echo -e "  ${BOLD}虚拟 IP 配置${NC}"
    echo -e "  ${CYAN} 1)${NC} 指定固定 IP"
    echo -e "  ${CYAN} 2)${NC} DHCP 自动分配（默认）"
    echo ""
    echo -n "  请选择 [1/2]（默认 2）: "
    read -r ip_choice

    local ip_config=""
    if [[ "$ip_choice" == "1" ]]; then
        echo -n "  输入固定 IP（如 10.144.144.2）: "
        read -r fixed_ip
        ip_config="ipv4 = \"${fixed_ip}\""
    else
        ip_config="dhcp = true"
    fi

    echo ""
    echo -n "  是否启用子网代理（将本地网络分享给VPN）？(y/N): "
    read -r proxy_choice
    local proxy_config=""
    if [[ "$proxy_choice" =~ ^[Yy]$ ]]; then
        echo -n "  输入要代理的子网（如 192.168.1.0/24）: "
        read -r proxy_net
        proxy_config="proxy_networks = [\"${proxy_net}\"]"
    fi

    echo ""
    echo -n "  是否启用 SOCKS5 代理？(y/N): "
    read -r socks_choice
    local socks_config=""
    if [[ "$socks_choice" =~ ^[Yy]$ ]]; then
        echo -n "  SOCKS5 端口（默认 1080）: "
        read -r socks_port
        socks_port="${socks_port:-1080}"
        socks_config="socks5 = ${socks_port}"
    fi

    echo ""
    echo -n "  指定出口节点（转发所有流量到该节点）？(y/N): "
    read -r exit_choice
    local exit_config=""
    if [[ "$exit_choice" =~ ^[Yy]$ ]]; then
        echo -n "  出口节点虚拟 IP: "
        read -r exit_ip
        exit_config="exit_nodes = [\"${exit_ip}\"]"
    fi

    # 生成 TOML
    cat <<EOF
# EasyTier 客户端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

network_name = "${net_name}"
network_secret = "${net_secret}"

${ip_config}

peers = ["tcp://${server_addr}"]

hostname = "$(hostname)-client"

${proxy_config}
${socks_config}
${exit_config}
EOF
}

client_show_status() {
    sep
    echo -e "${BOLD}              客户端连接状态${NC}"
    sep
    echo ""

    if is_docker_installed; then
        docker exec "$CONTAINER_NAME" easytier-cli peer 2>/dev/null || warn "无法获取状态"
        echo ""
        docker exec "$CONTAINER_NAME" easytier-cli route 2>/dev/null || warn "无法获取路由"
    elif is_installed; then
        easytier-cli peer 2>/dev/null || warn "无法获取状态"
        echo ""
        easytier-cli route 2>/dev/null || warn "无法获取路由"
    else
        warn "EasyTier 未安装"
    fi

    sep
}

client_modify_config() {
    if [[ ! -f "${CONFIG_DIR}/client.toml" ]]; then
        error "未找到客户端配置"
        return
    fi

    sep
    echo -e "${BOLD}              修改客户端配置${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 修改服务端地址"
    echo -e "  ${CYAN} 2)${NC} 修改网络名称 / 密码"
    echo -e "  ${CYAN} 3)${NC} 修改虚拟 IP（固定/DHCP）"
    echo -e "  ${CYAN} 4)${NC} 子网代理配置"
    echo -e "  ${CYAN} 5)${NC} 高级选项（SOCKS5/出口节点/加密等）"
    echo -e "  ${CYAN} 6)${NC} 使用编辑器修改配置文件"
    echo ""
    echo -n "请选择: "
    read -r mod_choice

    case "$mod_choice" in
        1)
            echo -n "  新服务端地址（如 1.2.3.4:11010）: "
            read -r new_addr
            if [[ -n "$new_addr" ]]; then
                sed -i "s|peers = .*|peers = [\"tcp://${new_addr}\"]|" "${CONFIG_DIR}/client.toml"
                ok "服务端地址已更新"
            fi
            ;;
        2)
            echo -n "  新网络名称: "
            read -r new_name
            echo -n "  新网络密码: "
            read -r new_secret
            [[ -n "$new_name" ]] && sed -i "s/network_name = .*/network_name = \"${new_name}\"/" "${CONFIG_DIR}/client.toml"
            [[ -n "$new_secret" ]] && sed -i "s/network_secret = .*/network_secret = \"${new_secret}\"/" "${CONFIG_DIR}/client.toml"
            ok "网络名称/密码已更新"
            ;;
        3)
            echo -e "  ${CYAN} 1)${NC} 指定固定 IP"
            echo -e "  ${CYAN} 2)${NC} DHCP 自动分配"
            echo -n "  请选择: "
            read -r ip_choice
            if [[ "$ip_choice" == "2" ]]; then
                sed -i '/^ipv4 = /d' "${CONFIG_DIR}/client.toml"
                grep -q "^dhcp = true" "${CONFIG_DIR}/client.toml" || echo "dhcp = true" >> "${CONFIG_DIR}/client.toml"
                ok "已切换到 DHCP 自动分配"
            else
                echo -n "  输入固定 IP: "
                read -r new_ip
                sed -i '/^dhcp = /d' "${CONFIG_DIR}/client.toml"
                if grep -q "^ipv4 = " "${CONFIG_DIR}/client.toml"; then
                    sed -i "s|ipv4 = .*|ipv4 = \"${new_ip}\"|" "${CONFIG_DIR}/client.toml"
                else
                    echo "ipv4 = \"${new_ip}\"" >> "${CONFIG_DIR}/client.toml"
                fi
                ok "虚拟 IP 已更新为 ${new_ip}"
            fi
            ;;
        4)
            echo -n "  输入子网（如 192.168.1.0/24，空则删除）: "
            read -r new_proxy
            sed -i '/proxy_networks/d' "${CONFIG_DIR}/client.toml"
            if [[ -n "$new_proxy" ]]; then
                echo "proxy_networks = [\"${new_proxy}\"]" >> "${CONFIG_DIR}/client.toml"
                ok "子网代理已更新"
            else
                ok "子网代理已删除"
            fi
            ;;
        5)
            client_advanced_config
            return
            ;;
        6)
            local editor=""
            for ed in nano vim vi; do
                command -v "$ed" &>/dev/null && { editor="$ed"; break; }
            done
            [[ -n "$editor" ]] && "$editor" "${CONFIG_DIR}/client.toml"
            ;;
    esac

    echo ""
    echo -n "  是否重启服务以生效？(Y/n): "
    read -r restart
    if [[ ! "$restart" =~ ^[Nn]$ ]]; then
        restart_service
    fi
}

client_advanced_config() {
    echo ""
    echo -e "  ${BOLD}高级选项配置${NC}"
    echo ""

    echo -n "  SOCKS5 端口（空则禁用）: "
    read -r socks_port
    sed -i '/^socks5/d' "${CONFIG_DIR}/client.toml"
    [[ -n "$socks_port" ]] && echo "socks5 = ${socks_port}" >> "${CONFIG_DIR}/client.toml"

    echo -n "  出口节点虚拟 IP（空则禁用）: "
    read -r exit_ip
    sed -i '/^exit_nodes/d' "${CONFIG_DIR}/client.toml"
    [[ -n "$exit_ip" ]] && echo "exit_nodes = [\"${exit_ip}\"]" >> "${CONFIG_DIR}/client.toml"

    echo -n "  启用延迟优先模式？(y/N): "
    read -r latency
    sed -i '/^latency_first/d' "${CONFIG_DIR}/client.toml"
    [[ "$latency" =~ ^[Yy]$ ]] && echo "latency_first = true" >> "${CONFIG_DIR}/client.toml"

    echo -n "  禁用 P2P（强制中继）？(y/N): "
    read -r no_p2p
    sed -i '/^disable_p2p/d' "${CONFIG_DIR}/client.toml"
    [[ "$no_p2p" =~ ^[Yy]$ ]] && echo "disable_p2p = true" >> "${CONFIG_DIR}/client.toml"

    echo -n "  启用魔法 DNS？(y/N): "
    read -r dns
    sed -i '/^accept_dns/d' "${CONFIG_DIR}/client.toml"
    [[ "$dns" =~ ^[Yy]$ ]] && echo "accept_dns = true" >> "${CONFIG_DIR}/client.toml"

    ok "高级选项已更新"
}

client_show_config() {
    if [[ -f "${CONFIG_DIR}/client.toml" ]]; then
        sep
        echo -e "${BOLD}              客户端配置${NC}"
        sep
        echo ""
        cat "${CONFIG_DIR}/client.toml"
        sep
    else
        warn "未找到客户端配置"
    fi
}

#=============================================================================
# 公共管理函数
#=============================================================================

start_service() {
    if is_docker_installed && ! systemctl is-active --quiet easytier 2>/dev/null; then
        docker start "$CONTAINER_NAME" 2>/dev/null && ok "Docker 容器已启动" || warn "Docker 启动失败"
    else
        systemctl start easytier 2>/dev/null && ok "服务已启动" || warn "服务启动失败"
    fi
}

stop_service() {
    if is_docker_installed; then
        docker stop "$CONTAINER_NAME" 2>/dev/null && ok "Docker 容器已停止" || true
    fi
    systemctl stop easytier 2>/dev/null && ok "服务已停止" || true
}

restart_service() {
    stop_service
    sleep 1
    start_service
}

uninstall_easytier() {
    sep
    echo -e "${BOLD}              卸载 EasyTier${NC}"
    sep
    echo ""

    warn "此操作将删除 EasyTier 及其所有配置！"
    echo -n "  确认卸载？输入 YES: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    # 停止所有
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    systemctl stop easytier 2>/dev/null || true
    systemctl disable easytier 2>/dev/null || true

    # 清理
    rm -f /etc/systemd/system/easytier.service
    rm -rf "$CONFIG_DIR"
    rm -f "$ET_BIN" "$ET_CLI"

    systemctl daemon-reload
    ok "EasyTier 已卸载"
    sep
}

#=============================================================================
# 主循环
#=============================================================================

server_mode() {
    while true; do
        show_server_menu
        read -r choice
        echo ""

        case "$choice" in
            1) server_native_install ;;
            2) server_docker_install ;;
            3) server_list_peers ;;
            4) server_route_list ;;
            5) start_service ;;
            6) stop_service ;;
            7) restart_service ;;
            8) server_modify_config ;;
            9) server_modify_config ;; # 快捷到修改菜单
            10) server_modify_config ;; # 快捷到修改菜单
            11) server_modify_config ;; # 快捷到修改菜单
            12) server_modify_config ;; # 快捷到修改菜单
            13) server_show_config ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按 Enter 键继续..."
        read -r
    done
}

client_mode() {
    while true; do
        show_client_menu
        read -r choice
        echo ""

        case "$choice" in
            1) client_native_install ;;
            2) client_docker_install ;;
            3) client_show_status ;;
            4) client_show_status ;; # 路由和状态一起显示
            5) start_service ;;
            6) stop_service ;;
            7) restart_service ;;
            8) client_modify_config ;;
            9) client_modify_config ;; # 快捷到修改菜单
            10) client_modify_config ;; # 快捷到修改菜单
            11) client_modify_config ;; # 快捷到修改菜单
            12) client_modify_config ;; # 快捷到修改菜单
            13) client_show_config ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按 Enter 键继续..."
        read -r
    done
}

main() {
    check_root

    while true; do
        show_main_menu
        read -r choice
        echo ""

        case "$choice" in
            1) server_mode ;;
            2) client_mode ;;
            3) install_easytier ;;
            4) uninstall_easytier ;;
            0|q|Q)
                echo ""
                info "退出 EasyTier 管理脚本"
                echo ""
                exit 0
                ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按 Enter 键继续..."
        read -r
    done
}

main
