#!/bin/bash
#=============================================================================
# 3X-UI 面板管理脚本
# 功能：安装/配置/管理 3X-UI 面板（支持 VLESS/VMess/Trojan/Shadowsocks）
# 基于：https://github.com/MHSanaei/3x-ui
# 用法：chmod +x xui_manager.sh && sudo ./xui_manager.sh
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
sep()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
sep_s() { echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本：sudo $0"
    fi
}

#-------------------- 检测安装状态 --------------------
is_xui_installed() {
    [[ -f /usr/local/x-ui/x-ui.sh ]] || systemctl list-unit-files | grep -q "x-ui"
}

get_panel_info() {
    if [[ -f /usr/local/x-ui/bin/config.json ]]; then
        local port=$(grep -o '"port":[0-9]*' /usr/local/x-ui/bin/config.json 2>/dev/null | head -1 | sed 's/.*://')
        local webBase=$(grep -o '"webBasePath":"[^"]*"' /usr/local/x-ui/bin/config.json 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
        echo "${port:-unknown}|${webBase:-/}"
    else
        echo "unknown|/"
    fi
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}          3X-UI 面板管理脚本${NC}"
    echo -e "${YELLOW}  基于 Xray 的多协议代理面板${NC}"
    sep
    echo ""

    local xui_status="${RED}未安装${NC}"
    local panel_port=""
    local panel_path=""

    if is_xui_installed; then
        if systemctl is-active --quiet x-ui 2>/dev/null; then
            xui_status="${GREEN}运行中${NC}"
            local info=$(get_panel_info)
            panel_port=$(echo "$info" | cut -d'|' -f1)
            panel_path=$(echo "$info" | cut -d'|' -f2)
        else
            xui_status="${YELLOW}已安装（未运行）${NC}"
        fi
    fi

    echo -e "  ${BLUE}面板状态：${NC}${xui_status}"
    [[ -n "$panel_port" ]] && echo -e "  ${BLUE}面板端口：${NC}${CYAN}${panel_port}${NC}"
    [[ -n "$panel_path" && "$panel_path" != "/" ]] && echo -e "  ${BLUE}面板路径：${NC}${CYAN}${panel_path}${NC}"

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【部署】${NC}"
    echo -e "  ${CYAN} 1)${NC} 安装 3X-UI 面板（官方脚本）"
    echo -e "  ${CYAN} 2)${NC} 自定义安装（指定端口/路径/账户）"
    echo ""
    echo -e "  ${CYAN}【管理】${NC}"
    echo -e "  ${CYAN} 3)${NC} 查看面板访问信息"
    echo -e "  ${CYAN} 4)${NC} 启动面板"
    echo -e "  ${CYAN} 5)${NC} 停止面板"
    echo -e "  ${CYAN} 6)${NC} 重启面板"
    echo -e "  ${CYAN} 7)${NC} 查看运行状态 & 日志"
    echo ""
    echo -e "  ${CYAN}【配置】${NC}"
    echo -e "  ${CYAN} 8)${NC} 修改面板端口"
    echo -e "  ${CYAN} 9)${NC} 修改面板路径（webBasePath）"
    echo -e "  ${CYAN}10)${NC} 修改登录用户名/密码"
    echo -e "  ${CYAN}11)${NC} 查看面板配置"
    echo ""
    echo -e "  ${CYAN}【维护】${NC}"
    echo -e "  ${CYAN}12)${NC} 更新面板到最新版"
    echo -e "  ${CYAN}13)${NC} 设置面板 HTTPS（需要域名+证书）"
    echo -e "  ${CYAN}14)${NC} 备份/恢复面板配置"
    echo -e "  ${CYAN}15)${NC} 卸载面板"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：官方脚本安装 --------------------
install_official() {
    sep
    echo -e "${BOLD}              安装 3X-UI 面板（官方脚本）${NC}"
    sep
    echo ""

    warn "此操作将使用 3X-UI 官方安装脚本"
    echo -n "  确认安装？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "开始安装 3X-UI..."

    # 国内/国外源选择
    echo -n "  是否使用国内加速源？(Y/n): "
    read -r china_source

    local install_url=""
    if [[ ! "$china_source" =~ ^[Nn]$ ]]; then
        install_url="https://ghp.ci/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    else
        install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    fi

    bash <(curl -Ls "$install_url")

    echo ""
    if is_xui_installed; then
        ok "3X-UI 安装完成！"
        print_panel_info
    else
        error "安装似乎未成功，请检查日志"
    fi

    sep
}

#-------------------- 功能 2：自定义安装 --------------------
install_custom() {
    sep
    echo -e "${BOLD}              自定义安装 3X-UI 面板${NC}"
    sep
    echo ""

    # 先执行官方安装
    warn "先执行官方安装脚本..."
    echo -n "  是否使用国内加速源？(Y/n): "
    read -r china_source

    local install_url=""
    if [[ ! "$china_source" =~ ^[Nn]$ ]]; then
        install_url="https://ghp.ci/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    else
        install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    fi

    bash <(curl -Ls "$install_url")

    if ! is_xui_installed; then
        error "基础安装失败，无法继续自定义配置"
        return
    fi

    echo ""
    info "开始自定义配置..."

    # 面板端口
    echo -n "  面板端口（默认随机）: "
    read -r panel_port

    # 面板路径
    echo -n "  面板路径（如 /admin，默认 /）: "
    read -r panel_path
    panel_path="${panel_path:-/}"

    # 账户
    echo -n "  登录用户名（默认 admin）: "
    read -r panel_user
    panel_user="${panel_user:-admin}"

    echo -n "  登录密码（默认 admin）: "
    read -r panel_pass
    panel_pass="${panel_pass:-admin}"

    # 使用 x-ui 命令设置
    if [[ -f /usr/local/x-ui/x-ui.sh ]]; then
        cd /usr/local/x-ui

        [[ -n "$panel_port" ]] && {
            info "设置面板端口为 ${panel_port}..."
            /usr/local/x-ui/x-ui.sh set-port "$panel_port" 2>/dev/null || true
        }

        [[ -n "$panel_path" && "$panel_path" != "/" ]] && {
            info "设置面板路径为 ${panel_path}..."
            /usr/local/x-ui/x-ui.sh set-path "$panel_path" 2>/dev/null || true
        }

        info "设置登录账户..."
        /usr/local/x-ui/x-ui.sh set-user "$panel_user" "$panel_pass" 2>/dev/null || true

        ok "自定义配置完成"
    fi

    # 防火墙
    local final_port=$(get_panel_info | cut -d'|' -f1)
    [[ "$final_port" != "unknown" ]] && open_firewall "$final_port"

    echo ""
    print_panel_info
    sep
}

#-------------------- 功能 3：查看面板信息 --------------------
print_panel_info() {
    sep
    echo -e "${BOLD}                    3X-UI 面板访问信息${NC}"
    sep
    echo ""

    local server_ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
    local info=$(get_panel_info)
    local port=$(echo "$info" | cut -d'|' -f1)
    local path=$(echo "$info" | cut -d'|' -f2)

    if [[ "$port" == "unknown" ]]; then
        warn "无法获取面板端口，请检查安装状态"
        return
    fi

    echo -e "  ${BLUE}面板地址：${NC}${CYAN}http://${server_ip}:${port}${path}${NC}"
    echo -e "  ${BLUE}面板端口：${NC}${CYAN}${port}${NC}"
    echo -e "  ${BLUE}面板路径：${NC}${CYAN}${path}${NC}"

    # 尝试读取登录凭据
    if [[ -f /usr/local/x-ui/bin/config.json ]]; then
        local username=$(grep -o '"username":"[^"]*"' /usr/local/x-ui/bin/config.json 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
        local password=$(grep -o '"password":"[^"]*"' /usr/local/x-ui/bin/config.json 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
        [[ -n "$username" ]] && echo -e "  ${BLUE}用户名  ：${NC}${MAGENTA}${username}${NC}"
        [[ -n "$password" ]] && echo -e "  ${BLUE}密码    ：${NC}${MAGENTA}${password}${NC}"
    fi

    echo ""
    echo -e "  ${YELLOW}提示：${NC}"
    echo -e "  ${YELLOW}- 首次登录后请立即修改默认密码${NC}"
    echo -e "  ${YELLOW}- 建议配置 HTTPS（选项 13）${NC}"
    echo -e "  ${YELLOW}- 支持的协议：VLESS / VMess / Trojan / Shadowsocks${NC}"

    sep
}

show_panel_info() {
    print_panel_info
}

#-------------------- 功能 4/5/6：启动/停止/重启 --------------------
start_panel() {
    if systemctl start x-ui 2>/dev/null; then
        ok "面板已启动"
    else
        warn "启动失败，尝试 x-ui 命令..."
        /usr/local/x-ui/x-ui.sh start 2>/dev/null && ok "面板已启动" || error "启动失败"
    fi
}

stop_panel() {
    systemctl stop x-ui 2>/dev/null || /usr/local/x-ui/x-ui.sh stop 2>/dev/null || true
    ok "面板已停止"
}

restart_panel() {
    systemctl restart x-ui 2>/dev/null || /usr/local/x-ui/x-ui.sh restart 2>/dev/null
    ok "面板已重启"
}

#-------------------- 功能 7：查看状态 --------------------
show_status() {
    sep
    echo -e "${BOLD}              3X-UI 面板运行状态${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}服务状态：${NC}"
    systemctl status x-ui --no-pager 2>/dev/null || warn "服务未运行"

    echo ""
    echo -e "  ${BOLD}最近日志（20 行）：${NC}"
    journalctl -u x-ui --no-pager -n 20 2>/dev/null || warn "无法获取日志"

    echo ""
    echo -e "  ${BOLD}Xray 状态：${NC}"
    systemctl status xray --no-pager 2>/dev/null || warn "Xray 服务未运行"

    sep
}

#-------------------- 功能 8：修改端口 --------------------
change_port() {
    if ! is_xui_installed; then
        error "3X-UI 未安装"
        return
    fi

    local current=$(get_panel_info | cut -d'|' -f1)
    echo -n "  当前端口: ${current}，输入新端口: "
    read -r new_port

    if [[ -n "$new_port" ]]; then
        cd /usr/local/x-ui
        /usr/local/x-ui/x-ui.sh set-port "$new_port" 2>/dev/null || {
            # 手动修改
            sed -i "s/\"port\":[0-9]*/\"port\":${new_port}/" /usr/local/x-ui/bin/config.json
            restart_panel
        }
        open_firewall "$new_port"
        ok "端口已修改为 ${new_port}"
    fi
}

#-------------------- 功能 9：修改路径 --------------------
change_path() {
    if ! is_xui_installed; then
        error "3X-UI 未安装"
        return
    fi

    echo -n "  输入新面板路径（如 /admin）: "
    read -r new_path

    if [[ -n "$new_path" ]]; then
        cd /usr/local/x-ui
        /usr/local/x-ui/x-ui.sh set-path "$new_path" 2>/dev/null || {
            sed -i "s|\"webBasePath\":\"[^\"]*\"|\"webBasePath\":\"${new_path}\"|" /usr/local/x-ui/bin/config.json
            restart_panel
        }
        ok "面板路径已修改为 ${new_path}"
    fi
}

#-------------------- 功能 10：修改账户 --------------------
change_credentials() {
    if ! is_xui_installed; then
        error "3X-UI 未安装"
        return
    fi

    echo -n "  新用户名: "
    read -r new_user
    echo -n "  新密码: "
    read -r new_pass

    if [[ -n "$new_user" && -n "$new_pass" ]]; then
        cd /usr/local/x-ui
        /usr/local/x-ui/x-ui.sh set-user "$new_user" "$new_pass" 2>/dev/null || {
            # 手动修改
            sed -i "s|\"username\":\"[^\"]*\"|\"username\":\"${new_user}\"|" /usr/local/x-ui/bin/config.json
            sed -i "s|\"password\":\"[^\"]*\"|\"password\":\"${new_pass}\"|" /usr/local/x-ui/bin/config.json
            restart_panel
        }
        ok "账户已更新"
    fi
}

#-------------------- 功能 11：查看配置 --------------------
show_config() {
    if [[ -f /usr/local/x-ui/bin/config.json ]]; then
        sep
        echo -e "${BOLD}              面板配置${NC}"
        sep
        echo ""
        cat /usr/local/x-ui/bin/config.json | python3 -m json.tool 2>/dev/null || cat /usr/local/x-ui/bin/config.json
        sep
    else
        warn "未找到配置文件"
    fi
}

#-------------------- 功能 12：更新 --------------------
update_panel() {
    sep
    echo -e "${BOLD}              更新 3X-UI 面板${NC}"
    sep
    echo ""

    if ! is_xui_installed; then
        error "3X-UI 未安装"
        return
    fi

    echo -n "  是否使用国内加速源？(Y/n): "
    read -r china_source

    local install_url=""
    if [[ ! "$china_source" =~ ^[Nn]$ ]]; then
        install_url="https://ghp.ci/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    else
        install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    fi

    bash <(curl -Ls "$install_url")
    ok "更新完成"
    sep
}

#-------------------- 功能 13：设置 HTTPS --------------------
setup_https() {
    sep
    echo -e "${BOLD}              设置面板 HTTPS${NC}"
    sep
    echo ""

    if ! is_xui_installed; then
        error "3X-UI 未安装"
        return
    fi

    echo -e "  ${YELLOW}两种方式配置 HTTPS：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 使用 Let's Encrypt 自动证书（需要域名指向服务器）"
    echo -e "  ${CYAN} 2)${NC} 使用自定义证书路径（已有 .crt + .key）"
    echo ""
    echo -n "  请选择 [1/2]: "
    read -r https_choice

    case "$https_choice" in
        1)
            echo -n "  输入域名（如 panel.example.com）: "
            read -r domain
            echo -n "  输入邮箱（用于 ACME）: "
            read -r email

            # 安装 certbot
            if ! command -v certbot &>/dev/null; then
                info "安装 certbot..."
                if [[ -f /etc/debian_version ]]; then
                    apt-get update -qq && apt-get install -y certbot
                else
                    yum install -y certbot || dnf install -y certbot
                fi
            fi

            info "申请证书..."
            certbot certonly --standalone -d "$domain" --agree-tos -m "$email" --non-interactive 2>/dev/null || {
                error "证书申请失败，请检查域名解析"
                return
            }

            local cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
            local key="/etc/letsencrypt/live/${domain}/privkey.pem"

            # 设置面板证书
            cd /usr/local/x-ui
            /usr/local/x-ui/x-ui.sh set-cert "$cert" "$key" 2>/dev/null || {
                # 手动设置
                local config_file="/usr/local/x-ui/bin/config.json"
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg['cert'] = '$cert'
cfg['key'] = '$key'
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null || warn "手动设置证书失败，请手动编辑 config.json"
            }

            ok "HTTPS 已配置"
            echo -e "  ${GREEN}面板地址：https://${domain}:$(get_panel_info | cut -d'|' -f1)$(get_panel_info | cut -d'|' -f2)${NC}"
            ;;
        2)
            echo -n "  输入证书文件路径（.crt/.pem）: "
            read -r cert_path
            echo -n "  输入私钥文件路径（.key）: "
            read -r key_path

            cd /usr/local/x-ui
            /usr/local/x-ui/x-ui.sh set-cert "$cert_path" "$key_path" 2>/dev/null || {
                python3 -c "
import json
with open('/usr/local/x-ui/bin/config.json', 'r') as f:
    cfg = json.load(f)
cfg['cert'] = '$cert_path'
cfg['key'] = '$key_path'
with open('/usr/local/x-ui/bin/config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null || warn "手动设置失败"
            }
            ok "证书已设置"
            ;;
    esac

    restart_panel
    sep
}

#-------------------- 功能 14：备份/恢复 --------------------
backup_restore() {
    sep
    echo -e "${BOLD}              备份 / 恢复面板配置${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 备份当前配置"
    echo -e "  ${CYAN} 2)${NC} 恢复配置"
    echo ""
    echo -n "  请选择 [1/2]: "
    read -r br_choice

    case "$br_choice" in
        1)
            local backup_dir="/root/x-ui-backups"
            mkdir -p "$backup_dir"
            local backup_file="${backup_dir}/x-ui-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

            tar -czf "$backup_file" -C /usr/local/x-ui . 2>/dev/null && {
                ok "备份完成: ${backup_file}"
            } || error "备份失败"
            ;;
        2)
            echo -n "  输入备份文件路径: "
            read -r backup_file
            if [[ -f "$backup_file" ]]; then
                systemctl stop x-ui 2>/dev/null || true
                tar -xzf "$backup_file" -C /usr/local/x-ui 2>/dev/null && {
                    ok "恢复完成"
                    restart_panel
                } || error "恢复失败"
            else
                error "备份文件不存在"
            fi
            ;;
    esac

    sep
}

#-------------------- 功能 15：卸载 --------------------
uninstall_panel() {
    sep
    echo -e "${BOLD}              卸载 3X-UI 面板${NC}"
    sep
    echo ""

    warn "此操作将删除 3X-UI 面板及其所有配置和节点数据！"
    echo -n "  确认卸载？输入 YES: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    # 使用官方卸载
    if [[ -f /usr/local/x-ui/x-ui.sh ]]; then
        cd /usr/local/x-ui
        /usr/local/x-ui/x-ui.sh uninstall 2>/dev/null || {
            # 手动卸载
            systemctl stop x-ui 2>/dev/null || true
            systemctl disable x-ui 2>/dev/null || true
            rm -f /etc/systemd/system/x-ui.service
            rm -rf /usr/local/x-ui/
            systemctl daemon-reload
        }
    fi

    ok "3X-UI 已卸载"
    sep
}

#-------------------- 防火墙放行 --------------------
open_firewall() {
    local port=$1
    info "配置防火墙..."
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null
        ok "firewalld 已开放端口 ${port}"
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "${port}/tcp" 2>/dev/null || true
        ok "UFW 已开放端口 ${port}"
    fi
}

#-------------------- 主循环 --------------------
main() {
    check_root

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1)  install_official ;;
            2)  install_custom ;;
            3)  show_panel_info ;;
            4)  start_panel ;;
            5)  stop_panel ;;
            6)  restart_panel ;;
            7)  show_status ;;
            8)  change_port ;;
            9)  change_path ;;
            10) change_credentials ;;
            11) show_config ;;
            12) update_panel ;;
            13) setup_https ;;
            14) backup_restore ;;
            15) uninstall_panel ;;
            0|q|Q)
                echo ""
                info "退出 3X-UI 管理脚本"
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
