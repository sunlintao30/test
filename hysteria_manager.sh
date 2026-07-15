#!/bin/bash
#=============================================================================
# Hysteria 2 代理一键部署脚本（支持 DIY 配置）
# 功能：安装/配置/管理 Hysteria 2，支持多种 TLS/认证/伪装/混淆模式
# 用法：chmod +x hysteria_manager.sh && sudo ./hysteria_manager.sh
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
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}          Hysteria 2 代理一键部署（DIY 配置）${NC}"
    sep
    echo ""

    # 显示当前状态
    local status_line=""
    if systemctl is-active --quiet hysteria-server 2>/dev/null; then
        status_line="  ${BLUE}服务状态：${NC}${GREEN}运行中${NC}"
    else
        status_line="  ${BLUE}服务状态：${NC}${RED}未运行${NC}"
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        local current_port=$(grep "^listen:" "$CONFIG_FILE" 2>/dev/null | sed 's/listen://g' | xargs || echo "?")
        local current_auth=$(grep "type:" "$CONFIG_FILE" 2>/dev/null | grep -A1 "auth:" | tail -1 | awk '{print $2}' || echo "?")
        local current_cert=$(grep -q "acme:" "$CONFIG_FILE" 2>/dev/null && echo "ACME" || (grep -q "tls:" "$CONFIG_FILE" 2>/dev/null && echo "TLS" || echo "?"))

        echo -e "$status_line"
        echo -e "  ${BLUE}监听端口：${NC}${CYAN}${current_port}${NC}"
        echo -e "  ${BLUE}认证方式：${NC}${CYAN}${current_auth}${NC}"
        echo -e "  ${BLUE}证书模式：${NC}${CYAN}${current_cert}${NC}"
    else
        echo -e "$status_line"
    fi

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【部署】${NC}"
    echo -e "  ${CYAN} 1)${NC} 快速安装（推荐预设）"
    echo -e "  ${CYAN} 2)${NC} DIY 自定义安装（高级配置）"
    echo ""
    echo -e "  ${CYAN}【管理】${NC}"
    echo -e "  ${CYAN} 3)${NC} 查看连接信息 / 客户端配置"
    echo -e "  ${CYAN} 4)${NC} 启动 Hysteria"
    echo -e "  ${CYAN} 5)${NC} 停止 Hysteria"
    echo -e "  ${CYAN} 6)${NC} 重启 Hysteria"
    echo -e "  ${CYAN} 7)${NC} 查看运行状态 & 日志"
    echo ""
    echo -e "  ${CYAN}【维护】${NC}"
    echo -e "  ${CYAN} 8)${NC} 修改配置（编辑 YAML）"
    echo -e "  ${CYAN} 9)${NC} 更新 Hysteria"
    echo -e "  ${CYAN}10)${NC} 卸载 Hysteria"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：快速安装 --------------------
quick_install() {
    sep
    echo -e "${BOLD}              Hysteria 2 快速安装${NC}"
    sep
    echo ""

    install_hysteria

    echo ""
    echo -e "  ${YELLOW}快速安装将使用以下预设配置：${NC}"
    echo -e "    - 端口: 自动选择（443 或随机）"
    echo -e "    - 证书: 自签名（自动生成）"
    echo -e "    - 认证: 密码"
    echo -e "    - 带宽: 不限制"
    echo -e "    - 混淆: 不启用"
    echo -e "    - 伪装: 不启用"
    echo ""
    echo -n "  确认安装？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    # 生成配置
    local port=$(find_free_port)
    local password=$(openssl rand -base64 24 2>/dev/null | tr -d '=+/')
    local cert_file="${CONFIG_DIR}/server.crt"
    local key_file="${CONFIG_DIR}/server.key"

    info "生成自签名证书..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "$key_file" -out "$cert_file" \
        -subj "/CN=hysteria.local" 2>/dev/null
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    ok "证书已生成"

    # 创建配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# Hysteria 2 服务端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

listen: :${port}

tls:
  cert: ${cert_file}
  key: ${key_file}

auth:
  type: password
  password: ${password}

# 带宽限制（不限制则删除或设为 0）
# bandwidth:
#   up: 1 gbps
#   down: 1 gbps

# 速度测试
speedTest: true
EOF

    ok "配置文件已生成"

    # 防火墙
    open_firewall "$port"

    # 启动
    systemctl enable hysteria-server
    systemctl restart hysteria-server

    ok "Hysteria 2 已启动"

    print_client_info
}

#-------------------- 功能 2：DIY 自定义安装 --------------------
diy_install() {
    sep
    echo -e "${BOLD}              Hysteria 2 DIY 自定义安装${NC}"
    sep
    echo ""

    install_hysteria

    # ---- 1. 端口 ----
    echo -e "  ${BOLD}【1/7】监听端口${NC}"
    echo -e "  ${YELLOW}提示：建议使用 443（标准 HTTPS 端口）或其他常用端口${NC}"
    echo -n "  输入端口（默认 443）: "
    read -r port
    port="${port:-443}"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        warn "无效端口，使用 443"
        port=443
    fi

    # ---- 2. 证书配置 ----
    echo ""
    echo -e "  ${BOLD}【2/7】TLS 证书配置${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 自签名证书（快速，无需域名）"
    echo -e "  ${CYAN} 2)${NC} ACME 自动证书（需要域名指向服务器）"
    echo -e "  ${CYAN} 3)${NC} 自定义证书路径（已有证书）"
    echo ""
    echo -n "  请选择 [1/2/3]（默认 1）: "
    read -r cert_choice

    local tls_config=""
    local sni_domain=""

    case "$cert_choice" in
        2)
            echo -n "  输入域名（如 example.com）: "
            read -r domain
            echo -n "  输入邮箱（用于 ACME 注册）: "
            read -r email
            tls_config=$(cat <<EOF
acme:
  domains:
    - ${domain}
  email: ${email}
EOF
)
            sni_domain="$domain"
            ;;
        3)
            echo -n "  输入证书文件路径（.crt/.pem）: "
            read -r cert_path
            echo -n "  输入私钥文件路径（.key）: "
            read -r key_path
            tls_config=$(cat <<EOF
tls:
  cert: ${cert_path}
  key: ${key_path}
EOF
)
            echo -n "  输入 SNI 域名（用于客户端验证）: "
            read -r sni_domain
            ;;
        *)
            local cert_file="${CONFIG_DIR}/server.crt"
            local key_file="${CONFIG_DIR}/server.key"
            openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
                -keyout "$key_file" -out "$cert_file" \
                -subj "/CN=hysteria.local" 2>/dev/null
            chmod 600 "$key_file"
            chmod 644 "$cert_file"
            ok "自签名证书已生成"
            tls_config=$(cat <<EOF
tls:
  cert: ${cert_file}
  key: ${key_file}
EOF
)
            sni_domain="hysteria.local"
            ;;
    esac

    # ---- 3. 认证方式 ----
    echo ""
    echo -e "  ${BOLD}【3/7】认证方式${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 单密码（password）${GREEN}（推荐）${NC}"
    echo -e "  ${CYAN} 2)${NC} 多用户（userpass）"
    echo -e "  ${CYAN} 3)${NC} HTTP 后端验证"
    echo ""
    echo -n "  请选择 [1/2/3]（默认 1）: "
    read -r auth_choice

    local auth_config=""

    case "$auth_choice" in
        2)
            auth_config="auth:\n  type: userpass\n  userpass:"
            echo ""
            echo -e "  ${YELLOW}输入用户名密码（每行一个，格式：用户名:密码，空行结束）${NC}"
            while true; do
                echo -n "    用户名:密码（或直接 Enter 结束）: "
                read -r userpass
                [[ -z "$userpass" ]] && break
                auth_config="${auth_config}\n    ${userpass}"
            done
            ;;
        3)
            echo -n "  输入 HTTP 验证后端 URL: "
            read -r http_url
            auth_config=$(cat <<EOF
auth:
  type: http
  http:
    url: ${http_url}
    insecure: false
EOF
)
            ;;
        *)
            local password=$(openssl rand -base64 24 2>/dev/null | tr -d '=+/')
            echo -n "  输入密码（留空则自动生成）: "
            read -r input_pass
            password="${input_pass:-$password}"
            auth_config=$(cat <<EOF
auth:
  type: password
  password: ${password}
EOF
)
            ;;
    esac

    # ---- 4. 带宽限制 ----
    echo ""
    echo -e "  ${BOLD}【4/7】带宽限制${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 不限制（默认）"
    echo -e "  ${CYAN} 2)${NC} 限制上传/下载带宽"
    echo ""
    echo -n "  请选择 [1/2]（默认 1）: "
    read -r bw_choice

    local bandwidth_config=""

    if [[ "$bw_choice" == "2" ]]; then
        echo -n "  输入上传带宽（如 100 mbps）: "
        read -r bw_up
        echo -n "  输入下载带宽（如 100 mbps）: "
        read -r bw_down
        bandwidth_config=$(cat <<EOF

bandwidth:
  up: ${bw_up}
  down: ${bw_down}
EOF
)
    fi

    # ---- 5. 混淆（Salamander）----
    echo ""
    echo -e "  ${BOLD}【5/7】混淆（Salamander）${NC}"
    echo -e "  ${YELLOW}提示：如果网络针对性屏蔽了 QUIC/HTTP3，可启用混淆${NC}"
    echo ""
    echo -n "  是否启用 Salamander 混淆？(y/N): "
    read -r obfs_choice

    local obfs_config=""

    if [[ "$obfs_choice" =~ ^[Yy]$ ]]; then
        local obfs_pass=$(openssl rand -base64 16 2>/dev/null | tr -d '=+/')
        echo -n "  输入混淆密码（留空则自动生成）: "
        read -r input_obfs
        obfs_pass="${input_obfs:-$obfs_pass}"
        obfs_config=$(cat <<EOF

obfs:
  type: salamander
  salamander:
    password: ${obfs_pass}
EOF
)
    fi

    # ---- 6. 伪装（Masquerade）----
    echo ""
    echo -e "  ${BOLD}【6/7】伪装（Masquerade）${NC}"
    echo -e "  ${YELLOW}提示：让 Hysteria 服务器像普通网站一样响应 HTTP 请求${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 不启用（返回 404）"
    echo -e "  ${CYAN} 2)${NC} 反向代理（从其他网站获取内容）"
    echo -e "  ${CYAN} 3)${NC} 固定字符串"
    echo ""
    echo -n "  请选择 [1/2/3]（默认 1）: "
    read -r masq_choice

    local masq_config=""

    case "$masq_choice" in
        2)
            echo -n "  输入要代理的网站 URL（如 https://bing.com）: "
            read -r proxy_url
            masq_config=$(cat <<EOF

masquerade:
  type: proxy
  proxy:
    url: ${proxy_url}
    rewriteHost: true
EOF
)
            ;;
        3)
            echo -n "  输入要返回的内容: "
            read -r masq_content
            masq_config=$(cat <<EOF

masquerade:
  type: string
  string:
    content: "${masq_content}"
    headers:
      content-type: text/plain
    statusCode: 200
EOF
)
            ;;
    esac

    # ---- 7. 高级选项 ----
    echo ""
    echo -e "  ${BOLD}【7/7】高级选项${NC}"
    echo ""
    echo -n "  是否启用速度测试功能？(Y/n): "
    read -r speedtest_choice
    local speedtest="true"
    [[ "$speedtest_choice" =~ ^[Nn]$ ]] && speedtest="false"

    echo ""
    echo -n "  是否禁用 UDP 转发（仅 TCP）？(y/N): "
    read -r disable_udp
    local udp_config=""
    [[ "$disable_udp" =~ ^[Yy]$ ]] && udp_config="\ndisableUDP: true"

    # 生成完整配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# Hysteria 2 服务端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 部署方式: DIY 自定义

listen: :${port}

${tls_config}

${auth_config}
${bandwidth_config}
${obfs_config}
${masq_config}

speedTest: ${speedtest}${udp_config}

# QUIC 参数（默认已优化，如需调整请取消注释）
# quic:
#   initStreamReceiveWindow: 8388608
#   maxStreamReceiveWindow: 8388608
#   initConnReceiveWindow: 20971520
#   maxConnReceiveWindow: 20971520
#   maxIdleTimeout: 30s
#   maxIncomingStreams: 1024

# 拥塞控制（默认 BBR）
# congestion:
#   type: bbr
EOF

    ok "配置文件已生成"

    # 防火墙
    open_firewall "$port"

    # 启动
    systemctl enable hysteria-server
    systemctl restart hysteria-server

    ok "Hysteria 2 已启动"

    print_client_info
}

#-------------------- 安装 Hysteria --------------------
install_hysteria() {
    if command -v hysteria &>/dev/null; then
        ok "Hysteria 已安装"
        return
    fi

    info "安装 Hysteria 2..."

    # 使用官方安装脚本
    bash <(curl -fsSL https://get.hy2.sh/) 2>/dev/null || {
        warn "官方脚本失败，尝试备用方式..."
        # 手动下载
        local arch=$(uname -m)
        local hy_arch=""
        case "$arch" in
            x86_64)  hy_arch="amd64" ;;
            aarch64) hy_arch="arm64" ;;
            armv7l)  hy_arch="armv7" ;;
            *)       hy_arch="amd64" ;;
        esac

        local latest=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        local url="https://github.com/apernet/hysteria/releases/download/${latest}/hysteria-linux-${hy_arch}"

        curl -fsSL "$url" -o /usr/local/bin/hysteria
        chmod +x /usr/local/bin/hysteria
    }

    ok "Hysteria 2 安装完成: $(hysteria version 2>/dev/null | head -1 || echo 'unknown')"
}

#-------------------- 查找空闲端口 --------------------
find_free_port() {
    local port=443
    if ss -tln 2>/dev/null | grep -q ":${port} "; then
        port=$((RANDOM % 40000 + 10000))
        while ss -tln 2>/dev/null | grep -q ":${port} "; do
            port=$((RANDOM % 40000 + 10000))
        done
    fi
    echo "$port"
}

#-------------------- 防火墙放行 --------------------
open_firewall() {
    local port=$1
    info "配置防火墙..."

    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/udp" 2>/dev/null
        firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        ok "firewalld 已开放端口 ${port}"
    fi

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "${port}/udp" 2>/dev/null
        ufw allow "${port}/tcp" 2>/dev/null
        ok "UFW 已开放端口 ${port}"
    fi

    # 如果都没有，尝试 iptables
    if command -v iptables &>/dev/null; then
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
}

#-------------------- 显示客户端连接信息 --------------------
print_client_info() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "未找到配置文件"
        return
    fi

    local server_ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
    local port=$(grep "^listen:" "$CONFIG_FILE" | sed 's/listen://g' | xargs | sed 's/://g')
    local password=$(grep -A2 "auth:" "$CONFIG_FILE" | grep "password:" | head -1 | awk '{print $2}')
    local obfs_pass=$(grep -A2 "salamander:" "$CONFIG_FILE" | grep "password:" | head -1 | awk '{print $2}')
    local sni=""

    if grep -q "acme:" "$CONFIG_FILE"; then
        sni=$(grep "domains:" -A1 "$CONFIG_FILE" | tail -1 | xargs | sed 's/- //')
    elif grep -q "tls:" "$CONFIG_FILE"; then
        sni=$(openssl x509 -in "$(grep "cert:" "$CONFIG_FILE" | awk '{print $2}')" -noout -subject 2>/dev/null | sed 's/.*CN=//' || echo "")
        [[ -z "$sni" ]] && sni="hysteria.local"
    fi

    sep
    echo -e "${BOLD}                    Hysteria 2 客户端配置${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}服务器地址：${NC}${CYAN}${server_ip}${NC}"
    echo -e "  ${BLUE}端口    ：${NC}${CYAN}${port}${NC}"
    [[ -n "$password" ]] && echo -e "  ${BLUE}密码    ：${NC}${MAGENTA}${password}${NC}"
    [[ -n "$obfs_pass" ]] && echo -e "  ${BLUE}混淆密码：${NC}${MAGENTA}${obfs_pass}${NC}"
    [[ -n "$sni" ]] && echo -e "  ${BLUE}SNI     ：${NC}${CYAN}${sni}${NC}"

    echo ""
    echo -e "  ${GREEN}${BOLD}客户端 YAML 配置示例：${NC}"
    echo ""
    echo -e "${CYAN}server: ${server_ip}:${port}${NC}"
    echo -e "${CYAN}auth: ${password}${NC}"
    [[ -n "$obfs_pass" ]] && echo -e "${CYAN}obfs:\n  type: salamander\n  salamander:\n    password: ${obfs_pass}${NC}"
    echo -e "${CYAN}tls:\n  sni: ${sni}${NC}"
    echo -e "${CYAN}  insecure: true${NC}"
    echo -e "${CYAN}bandwidth:\n  up: 100 mbps\n  down: 100 mbps${NC}"
    echo -e "${CYAN}fastOpen: true${NC}"
    echo -e "${CYAN}socks5:\n  listen: 127.0.0.1:1080${NC}"
    echo -e "${CYAN}http:\n  listen: 127.0.0.1:8080${NC}"

    echo ""
    echo -e "  ${YELLOW}提示：${NC}"
    echo -e "  ${YELLOW}- 使用自签名证书时，客户端需设置 tls.insecure: true${NC}"
    echo -e "  ${YELLOW}- 使用 ACME 证书时，客户端 tls.insecure 可设为 false${NC}"
    echo -e "  ${YELLOW}- 带宽设置建议等于或略低于实际网络带宽${NC}"
    echo -e "  ${YELLOW}- 客户端下载：https://github.com/apernet/hysteria/releases${NC}"

    sep
}

#-------------------- 功能 3：查看连接信息 --------------------
show_info() {
    print_client_info
}

#-------------------- 功能 4/5/6：启动/停止/重启 --------------------
start_hysteria() {
    systemctl start hysteria-server 2>/dev/null || {
        warn "服务启动失败，尝试重新加载配置..."
        systemctl daemon-reload
        systemctl start hysteria-server
    }
    ok "Hysteria 已启动"
}

stop_hysteria() {
    systemctl stop hysteria-server 2>/dev/null || true
    ok "Hysteria 已停止"
}

restart_hysteria() {
    systemctl daemon-reload
    systemctl restart hysteria-server
    ok "Hysteria 已重启"
}

#-------------------- 功能 7：查看状态 --------------------
show_status() {
    sep
    echo -e "${BOLD}              Hysteria 2 运行状态${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}服务状态：${NC}"
    systemctl status hysteria-server --no-pager 2>/dev/null || warn "服务未运行"

    echo ""
    echo -e "  ${BOLD}最近日志（20 行）：${NC}"
    journalctl -u hysteria-server --no-pager -n 20 2>/dev/null || warn "无法获取日志"

    sep
}

#-------------------- 功能 8：修改配置 --------------------
edit_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "未找到配置文件"
        return
    fi

    sep
    echo -e "${BOLD}              编辑 Hysteria 配置${NC}"
    sep
    echo ""

    # 检测可用编辑器
    local editor=""
    for ed in nano vim vi; do
        if command -v "$ed" &>/dev/null; then
            editor="$ed"
            break
        fi
    done

    if [[ -z "$editor" ]]; then
        error "未找到可用编辑器（nano/vim/vi）"
        return
    fi

    info "使用 ${editor} 编辑配置..."
    "$editor" "$CONFIG_FILE"

    echo ""
    info "验证配置..."
    if hysteria server --config "$CONFIG_FILE" --dry-run 2>/dev/null; then
        ok "配置验证通过"
    else
        warn "配置可能有语法错误，请检查"
    fi

    echo ""
    echo -n "  是否重启服务以应用更改？(Y/n): "
    read -r restart
    if [[ ! "$restart" =~ ^[Nn]$ ]]; then
        restart_hysteria
    fi

    sep
}

#-------------------- 功能 9：更新 --------------------
update_hysteria() {
    sep
    echo -e "${BOLD}              更新 Hysteria 2${NC}"
    sep
    echo ""

    local current=$(hysteria version 2>/dev/null | head -1 || echo "unknown")
    info "当前版本: ${current}"

    info "检查更新..."
    bash <(curl -fsSL https://get.hy2.sh/) 2>/dev/null || {
        error "更新失败"
        return
    }

    local new=$(hysteria version 2>/dev/null | head -1 || echo "unknown")
    ok "更新完成: ${new}"

    restart_hysteria
    sep
}

#-------------------- 功能 10：卸载 --------------------
uninstall_hysteria() {
    sep
    echo -e "${BOLD}              卸载 Hysteria 2${NC}"
    sep
    echo ""

    warn "此操作将删除 Hysteria 2 及其所有配置！"
    echo -n "  确认卸载？输入 YES: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    systemctl stop hysteria-server 2>/dev/null || true
    systemctl disable hysteria-server 2>/dev/null || true

    # 清理文件
    rm -f "$SERVICE_FILE"
    rm -rf "$CONFIG_DIR"
    rm -f /usr/local/bin/hysteria

    systemctl daemon-reload

    ok "Hysteria 2 已卸载"
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
            1)  quick_install ;;
            2)  diy_install ;;
            3)  show_info ;;
            4)  start_hysteria ;;
            5)  stop_hysteria ;;
            6)  restart_hysteria ;;
            7)  show_status ;;
            8)  edit_config ;;
            9)  update_hysteria ;;
            10) uninstall_hysteria ;;
            0|q|Q)
                echo ""
                info "退出 Hysteria 2 管理脚本"
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
