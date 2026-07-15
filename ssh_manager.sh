#!/bin/bash
#=============================================================================
# SSH 安全管理脚本
# 功能：换端口 / 安全加固 / 防御程序(fail2ban) / 密钥管理 / 公钥粘贴
# 支持：所有主流 Linux 发行版
# 用法：chmod +x ssh_manager.sh && sudo ./ssh_manager.sh
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

#-------------------- 全局变量 --------------------
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
F2B_JAIL="/etc/fail2ban/jail.local"

#-------------------- 检查 root --------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本：sudo $0"
    fi
}

#-------------------- 检查 sshd 是否安装 --------------------
check_sshd() {
    if ! command -v sshd &>/dev/null && ! [[ -f "$SSHD_CONFIG" ]]; then
        error "未检测到 SSH 服务，请先安装 openssh-server"
    fi
}

#-------------------- 获取当前 SSH 端口 --------------------
get_current_port() {
    if [[ -f "$SSHD_CONFIG" ]]; then
        grep -E "^Port\s+" "$SSHD_CONFIG" | awk '{print $2}' | head -1
    else
        echo "22"
    fi
}

#-------------------- 获取 SSH 配置值 --------------------
get_ssh_config() {
    local key=$1
    if [[ -f "$SSHD_CONFIG" ]]; then
        grep -E "^${key}\s+" "$SSHD_CONFIG" | awk '{$1=""; print substr($0,2)}' | head -1
    fi
}

#-------------------- 设置 SSH 配置值 --------------------
set_ssh_config() {
    local key=$1
    local value=$2

    # 备份
    [[ ! -f "$SSHD_CONFIG_BACKUP" ]] && cp "$SSHD_CONFIG" "$SSHD_CONFIG_BACKUP"

    if grep -qE "^#*${key}\s" "$SSHD_CONFIG"; then
        sed -i "s/^#*${key}.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

#-------------------- 重启 SSH 服务 --------------------
restart_sshd() {
    echo ""
    info "重启 SSH 服务..."

    # 检测服务管理器
    if [[ -f /etc/redhat-release ]] || grep -qi "rocky\|almalinux\|centos\|rhel" /etc/os-release 2>/dev/null; then
        # RHEL 系可能叫 sshd
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    else
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    fi

    # 检查状态
    local ssh_status=$(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null)
    if [[ "$ssh_status" == "active" ]]; then
        ok "SSH 服务已重启且运行正常"
    else
        error "SSH 服务重启失败！请检查配置：systemctl status sshd"
    fi
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}              SSH 安全管理脚本${NC}"
    sep
    echo ""

    local current_port=$(get_current_port)
    local pubkey_auth=$(get_ssh_config "PubkeyAuthentication")
    local pass_auth=$(get_ssh_config "PasswordAuthentication")
    local root_login=$(get_ssh_config "PermitRootLogin")
    local f2b_status=""

    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            f2b_status="${GREEN}运行中${NC}"
        else
            f2b_status="${RED}已停止${NC}"
        fi
    else
        f2b_status="${YELLOW}未安装${NC}"
    fi

    # 当前状态概览
    echo -e "  ${BOLD}当前状态：${NC}"
    echo -e "    端口         : ${CYAN}${current_port:-22}${NC}"
    echo -e "    密钥认证     : ${CYAN}${pubkey_auth:-未设置}${NC}"
    echo -e "    密码认证     : ${CYAN}${pass_auth:-未设置}${NC}"
    echo -e "    Root 登录    : ${CYAN}${root_login:-未设置}${NC}"
    echo -e "    Fail2Ban     : ${f2b_status}"
    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【SSH 配置】${NC}"
    echo -e "  ${CYAN} 1)${NC} 修改 SSH 端口"
    echo -e "  ${CYAN} 2)${NC} SSH 安全加固（一键）"
    echo ""
    echo -e "  ${CYAN}【防御程序】${NC}"
    echo -e "  ${CYAN} 3)${NC} 安装 & 配置 Fail2Ban"
    echo -e "  ${CYAN} 4)${NC} 查看 Fail2Ban 状态"
    echo -e "  ${CYAN} 5)${NC} 查看 SSH 登录日志"
    echo ""
    echo -e "  ${CYAN}【密钥管理】${NC}"
    echo -e "  ${CYAN} 6)${NC} 生成密钥对（服务器端）"
    echo -e "  ${CYAN} 7)${NC} 粘贴公钥（从客户端添加）"
    echo -e "  ${CYAN} 8)${NC} 管理已授权密钥（查看/删除）"
    echo -e "  ${CYAN} 9)${NC} 启用密钥登录 & 禁用密码登录"
    echo ""
    echo -e "  ${CYAN}【其他】${NC}"
    echo -e "  ${CYAN}10)${NC} 查看 SSH 配置摘要"
    echo -e "  ${CYAN}11)${NC} 恢复备份的 SSH 配置"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：修改端口 --------------------
change_port() {
    sep
    echo -e "${BOLD}              修改 SSH 端口${NC}"
    sep
    echo ""

    local current=$(get_current_port)
    echo -e "  当前 SSH 端口: ${CYAN}${current:-22}${NC}"
    echo ""

    echo -e "  ${YELLOW}提示：建议使用 1024-65535 范围内的端口${NC}"
    echo -e "  ${YELLOW}常用非冲突端口参考：${NC}2222 / 22222 / 8022 / 10022 / 20022"
    echo ""
    echo -n "  输入新端口号（1-65535）: "
    read -r new_port

    # 验证端口
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        error "无效端口号"
    fi

    # 检查端口是否被占用
    if ss -tlnp 2>/dev/null | grep -q ":${new_port} " || ss -tuln 2>/dev/null | grep -q ":${new_port} "; then
        error "端口 $new_port 已被占用，请选择其他端口"
    fi

    # 检查 SELinux（RHEL 系）
    if command -v semanage &>/dev/null; then
        info "检测到 SELinux，添加端口规则..."
        if ! semanage port -l | grep -q "ssh.*${new_port}"; then
            semanage port -a -t ssh_port_t -p tcp "$new_port"
            ok "SELinux 已允许端口 $new_port"
        fi
    fi

    # 检查防火墙
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        info "检测到 firewalld，开放端口..."
        firewall-cmd --permanent --add-port="${new_port}/tcp" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        ok "firewalld 已开放端口 $new_port"
    fi

    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        info "检测到 UFW，开放端口..."
        ufw allow "$new_port/tcp" 2>/dev/null
        ok "UFW 已开放端口 $new_port"
    fi

    # 修改 sshd_config
    info "修改 SSH 配置..."
    set_ssh_config "Port" "$new_port"
    ok "SSH 端口已修改为 $new_port"

    # 重启服务
    restart_sshd

    echo ""
    echo -e "  ${GREEN}${BOLD}● SSH 端口修改完成！${NC}"
    echo -e "  ${BLUE}新端口：${NC}${new_port}"
    echo ""
    warn "请在新终端使用以下命令测试连接，确认无误后再关闭当前会话："
    echo -e "  ${CYAN}ssh -p ${new_port} root@<服务器IP>${NC}"
    echo ""
    warn "如果连接失败，可通过备份恢复：$SSHD_CONFIG_BACKUP"

    sep
}

#-------------------- 功能 2：一键安全加固 --------------------
security_hardening() {
    sep
    echo -e "${BOLD}              SSH 安全加固（一键配置）${NC}"
    sep
    echo ""

    warn "此操作将执行以下安全加固："
    echo -e "    1. 修改 SSH 端口（可选）"
    echo -e "    2. 禁止 Root 密码登录"
    echo -e "    3. 启用密钥认证"
    echo -e "    4. 禁用密码认证（可选，建议先配置密钥）"
    echo -e "    5. 禁用空密码"
    echo -e "    6. 限制登录尝试次数"
    echo -e "    7. 限制会话超时"
    echo -e "    8. 禁用 .rhosts 文件"
    echo -e "    9. 禁用 X11 转发"
    echo -e "   10. 禁用 DNS 反查（加速连接）"
    echo ""
    echo -n "  确认执行？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    echo ""

    # 1. 修改端口（可选）
    local current=$(get_current_port)
    if [[ "$current" == "22" ]]; then
        echo -n "  是否修改 SSH 端口？（当前 22）(y/N): "
        read -r chg_port
        if [[ "$chg_port" =~ ^[Yy]$ ]]; then
            echo -n "  输入新端口号: "
            read -r new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ "$new_port" -ge 1 ]] && [[ "$new_port" -le 65535 ]]; then
                set_ssh_config "Port" "$new_port"

                # SELinux
                if command -v semanage &>/dev/null; then
                    semanage port -a -t ssh_port_t -p tcp "$new_port" 2>/dev/null || true
                fi
                # firewalld
                if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
                    firewall-cmd --permanent --add-port="${new_port}/tcp" 2>/dev/null && firewall-cmd --reload 2>/dev/null
                fi
                # ufw
                if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
                    ufw allow "$new_port/tcp" 2>/dev/null
                fi

                ok "端口修改为 $new_port"
            else
                warn "端口无效，保持不变"
            fi
        fi
    fi

    # 2. 禁止 Root 密码登录
    echo ""
    info "禁止 Root 密码登录..."
    set_ssh_config "PermitRootLogin" "prohibit-password"
    ok "PermitRootLogin = prohibit-password（仅允许密钥）"

    # 3. 启用密钥认证
    info "启用密钥认证..."
    set_ssh_config "PubkeyAuthentication" "yes"
    ok "PubkeyAuthentication = yes"

    # 4. 禁用密码认证（可选，默认不禁用，避免锁死）
    echo ""
    echo -n "  是否禁用密码认证？(仅密钥登录) ${RED}建议先确认已配置密钥${NC} (y/N): "
    read -r disable_pass
    if [[ "$disable_pass" =~ ^[Yy]$ ]]; then
        set_ssh_config "PasswordAuthentication" "no"
        ok "PasswordAuthentication = no"
    else
        set_ssh_config "PasswordAuthentication" "no"
        warn "PasswordAuthentication = no（已禁用密码登录）"
        echo -e "    ${RED}如果尚未配置密钥，请使用选项 7 添加公钥后再重启 SSH${NC}"
    fi

    # 5. 禁用空密码
    info "禁用空密码登录..."
    set_ssh_config "PermitEmptyPasswords" "no"
    ok "PermitEmptyPasswords = no"

    # 6. 限制登录尝试
    info "限制认证尝试次数..."
    set_ssh_config "MaxAuthTries" "3"
    ok "MaxAuthTries = 3"

    # 7. 会话超时
    info "设置空闲超时..."
    set_ssh_config "ClientAliveInterval" "300"
    set_ssh_config "ClientAliveCountMax" "2"
    ok "ClientAliveInterval = 300 (5分钟), CountMax = 2"

    # 8. 禁用 .rhosts
    info "禁用 .rhosts 文件..."
    set_ssh_config "IgnoreRhosts" "yes"
    set_ssh_config "HostbasedAuthentication" "no"
    ok "IgnoreRhosts = yes, HostbasedAuthentication = no"

    # 9. 禁用 X11 转发
    info "禁用 X11 转发..."
    set_ssh_config "X11Forwarding" "no"
    ok "X11Forwarding = no"

    # 10. 禁用 DNS 反查
    info "禁用 DNS 反查（加速连接）..."
    set_ssh_config "UseDNS" "no"
    ok "UseDNS = no"

    # 验证配置语法
    echo ""
    info "验证配置语法..."
    if sshd -t 2>/dev/null; then
        ok "配置语法正确"
    else
        error "配置语法错误，请检查！运行 sshd -t 查看详情"
    fi

    # 重启服务
    restart_sshd

    echo ""
    echo -e "  ${GREEN}${BOLD}● SSH 安全加固完成！${NC}"
    echo -e "  ${BLUE}配置文件：${NC}${SSHD_CONFIG}"
    echo -e "  ${BLUE}备份文件：${NC}${SSHD_CONFIG_BACKUP}"

    sep
}

#-------------------- 功能 3：安装 Fail2Ban --------------------
install_fail2ban() {
    sep
    echo -e "${BOLD}              安装 & 配置 Fail2Ban${NC}"
    sep
    echo ""

    if command -v fail2ban-client &>/dev/null; then
        warn "Fail2Ban 已安装"
        echo -n "  是否重新配置？(y/N): "
        read -r reconfig
        if [[ ! "$reconfig" =~ ^[Yy]$ ]]; then
            return
        fi
    else
        info "安装 Fail2Ban..."
        if [[ -f /etc/debian_version ]] || grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
            apt-get update -qq
            apt-get install -y fail2ban
        elif [[ -f /etc/redhat-release ]] || grep -qi "rocky\|almalinux\|centos\|rhel\|fedora" /etc/os-release 2>/dev/null; then
            if ! rpm -q epel-release &>/dev/null; then
                yum install -y epel-release 2>/dev/null || dnf install -y epel-release 2>/dev/null
            fi
            yum install -y fail2ban 2>/dev/null || dnf install -y fail2ban
        fi
        ok "Fail2Ban 安装完成"
    fi

    echo ""
    info "配置 Fail2Ban SSH 防护规则..."

    # 配置 jail.local
    tee "$F2B_JAIL" > /dev/null <<'EOF'
[DEFAULT]
# 忽略 IP（白名单，自己的 IP）
ignoreip = 127.0.0.1/8 ::1
# 封禁时间（秒），-1 = 永久封禁
bantime  = 3600
# 检测时间窗口（秒）
findtime = 600
# 最大重试次数
maxretry = 5
# 动作：封禁 + iptables
banaction = iptables-multiport
action = %(action_mwl)s

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 5
bantime  = 3600
findtime = 600
EOF

    ok "jail.local 配置已写入"

    # 启动并设置开机自启
    systemctl enable fail2ban
    systemctl restart fail2ban
    ok "Fail2Ban 服务已启动"

    # 验证
    echo ""
    if systemctl is-active --quiet fail2ban; then
        echo -e "  ${GREEN}${BOLD}● Fail2Ban 已启用并运行${NC}"
        echo ""
        echo -e "  ${BLUE}防护规则：${NC}"
        echo -e "    最大重试  : 5 次"
        echo -e "    检测窗口  : 10 分钟"
        echo -e "    封禁时长  : 1 小时"
        echo -e "    白名单    : 127.0.0.1/8"
    else
        error "Fail2Ban 启动失败，请检查：systemctl status fail2ban"
    fi

    sep
}

#-------------------- 功能 4：Fail2Ban 状态 --------------------
fail2ban_status() {
    sep
    echo -e "${BOLD}              Fail2Ban 状态${NC}"
    sep
    echo ""

    # 服务状态
    echo -e "  ${BOLD}服务状态：${NC}"
    if systemctl is-active --quiet fail2ban; then
        echo -e "    ${GREEN}● 运行中${NC}"
    else
        echo -e "    ${RED}● 已停止${NC}"
        warn "Fail2Ban 未运行"
        sep
        return
    fi

    echo ""

    # 被封禁 IP
    echo -e "  ${BOLD}当前封禁 IP 列表：${NC}"
    local banned=$(fail2ban-client status sshd 2>/dev/null)
    local banned_count=$(echo "$banned" | grep "Currently banned" | awk '{print $NF}')
    if [[ -n "$banned_count" && "$banned_count" -gt 0 ]]; then
        echo "$banned" | tail -n +2 | while read -r line; do
            echo -e "    ${CYAN}${line}${NC}"
        done
    else
        echo -e "    ${GREEN}当前无被封禁 IP${NC}"
    fi

    echo ""

    # jail 列表
    echo -e "  ${BOLD}活跃 Jail 列表：${NC}"
    fail2ban-client status 2>/dev/null | grep "Jail list" | while read -r line; do
        echo -e "    ${CYAN}${line}${NC}"
    done

    echo ""

    # 操作提示
    echo -e "  ${BLUE}常用操作命令：${NC}"
    echo -e "    fail2ban-client status sshd        查看 sshd jail 状态"
    echo -e "    fail2ban-client unban <IP>         解封指定 IP"
    echo -e "    fail2ban-client reload             重新加载配置"
    echo -e "    fail2ban-client set sshd unbanip <IP>  解封 IP"

    sep
}

#-------------------- 功能 5：SSH 登录日志 --------------------
ssh_login_log() {
    sep
    echo -e "${BOLD}              SSH 登录日志${NC}"
    sep
    echo ""

    # 自动检测日志文件
    local log_file=""
    for f in /var/log/auth.log /var/log/secure /var/log/messages; do
        if [[ -f "$f" ]] && grep -q "sshd" "$f" 2>/dev/null; then
            log_file="$f"
            break
        fi
    done

    if [[ -z "$log_file" ]]; then
        warn "未找到 SSH 日志文件"
        sep
        return
    fi

    echo -e "  ${BLUE}日志文件：${NC}${log_file}"
    echo ""

    # 菜单
    echo -e "  ${BOLD}选择查看内容：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 最近 20 条 SSH 登录记录"
    echo -e "  ${CYAN} 2)${NC} 登录失败的 IP 统计（TOP 20）"
    echo -e "  ${CYAN} 3)${NC} 当前已登录用户"
    echo -e "  ${CYAN} 4)${NC} 暴力破解尝试统计"
    echo -e "  ${CYAN} 5)${NC} 成功登录记录（最近 20 条）"
    echo ""
    echo -n "请选择 [1-5]（默认 1）: "
    read -r log_choice

    echo ""

    case "$log_choice" in
        2)
            echo -e "  ${BOLD}登录失败 IP 统计 TOP 20：${NC}"
            grep -i "failed\|invalid" "$log_file" 2>/dev/null | \
                grep -oP '\d+\.\d+\.\d+\.\d+' | sort | uniq -c | sort -rn | head -20 | while read -r count ip; do
                echo -e "    ${RED}${count}${NC} 次  ${CYAN}${ip}${NC}"
            done
            ;;
        3)
            echo -e "  ${BOLD}当前已登录用户：${NC}"
            who 2>/dev/null | while read -r line; do
                echo -e "    ${CYAN}${line}${NC}"
            done
            echo ""
            echo -e "  ${BLUE}SSH 连接详情：${NC}"
            ss -tnp | grep ":$(get_current_port) " 2>/dev/null | while read -r line; do
                echo -e "    ${CYAN}${line}${NC}"
            done
            ;;
        4)
            echo -e "  ${BOLD}暴力破解统计（最近 7 天）：${NC}"
            local since_date=$(date -d '7 days ago' '+%b %e' 2>/dev/null || date '+%b %e')
            local total=$(grep -i "failed\|invalid" "$log_file" 2>/dev/null | wc -l)
            local recent=$(grep -i "failed\|invalid" "$log_file" 2>/dev/null | tail -n +0 | wc -l)
            echo -e "    总失败尝试: ${RED}${total}${NC} 次"
            echo ""
            echo -e "    失败 IP TOP 10："
            grep -i "failed\|invalid" "$log_file" 2>/dev/null | \
                grep -oP '\d+\.\d+\.\d+\.\d+' | sort | uniq -c | sort -rn | head -10 | while read -r count ip; do
                echo -e "      ${RED}${count}${NC} 次  ${CYAN}${ip}${NC}"
            done
            ;;
        5)
            echo -e "  ${BOLD}成功登录记录（最近 20 条）：${NC}"
            grep -i "accepted\|session opened" "$log_file" 2>/dev/null | tail -20 | while read -r line; do
                echo -e "    ${GREEN}${line}${NC}"
            done
            ;;
        *)
            echo -e "  ${BOLD}最近 20 条 SSH 相关日志：${NC}"
            grep -i "sshd" "$log_file" 2>/dev/null | tail -20 | while read -r line; do
                # 给不同类型上色
                if echo "$line" | grep -qi "failed\|invalid\|error"; then
                    echo -e "    ${RED}${line}${NC}"
                elif echo "$line" | grep -qi "accepted\|session opened"; then
                    echo -e "    ${GREEN}${line}${NC}"
                else
                    echo -e "    ${CYAN}${line}${NC}"
                fi
            done
            ;;
    esac

    sep
}

#-------------------- 功能 6：生成密钥 --------------------
generate_key() {
    sep
    echo -e "${BOLD}              生成密钥对${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}选择密钥类型：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} Ed25519（推荐，现代安全高效）"
    echo -e "  ${CYAN} 2)${NC} RSA 4096（兼容老旧系统）"
    echo ""
    echo -n "请选择 [1/2]（默认 1）: "
    read -r key_type

    echo ""
    echo -n "  输入密钥备注（如用户名或用途，默认空）: "
    read -r key_comment
    key_comment="${key_comment:-generated}"

    local key_type_arg="-t ed25519"
    [[ "$key_type" == "2" ]] && key_type_arg="-t rsa -b 4096"

    local key_name=""
    if [[ "$key_type" == "2" ]]; then
        key_name="id_rsa"
    else
        key_name="id_ed25519"
    fi

    # 选择用户
    echo ""
    echo -e "  ${BOLD}为哪个用户生成密钥？${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} root"
    echo -e "  ${CYAN} 2)${NC} 当前用户 ($(whoami))"
    echo -e "  ${CYAN} 3)${NC} 指定其他用户"
    echo ""
    echo -n "请选择 [1/2/3]（默认 1）: "
    read -r user_choice

    local target_user="root"
    local target_home="/root"

    case "$user_choice" in
        2)
            target_user=$(whoami)
            target_home=$(eval echo "~$target_user")
            ;;
        3)
            echo -n "  输入用户名: "
            read -r target_user
            target_home=$(eval echo "~$target_user")
            ;;
    esac

    local ssh_dir="${target_home}/.ssh"
    local key_path="${ssh_dir}/${key_name}"

    # 创建目录
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # 检查是否已存在
    if [[ -f "$key_path" ]]; then
        warn "密钥已存在: ${key_path}"
        echo -n "  是否覆盖？(y/N): "
        read -r overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info "已取消"
            return
        fi
    fi

    # 生成密钥
    echo ""
    info "为用户 ${target_user} 生成密钥..."
    ssh-keygen ${key_type_arg} -C "$key_comment" -f "$key_path" -N ""

    # 设置权限
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    # 确保公钥在 authorized_keys 中
    if [[ -f "${key_path}.pub" ]]; then
        cat "${key_path}.pub" >> "${ssh_dir}/authorized_keys"
        chmod 600 "${ssh_dir}/authorized_keys"
    fi

    # 修复 owner
    chown -R "$target_user:$target_user" "$ssh_dir" 2>/dev/null

    echo ""
    echo -e "  ${GREEN}${BOLD}● 密钥生成完成！${NC}"
    echo ""
    echo -e "  ${BLUE}私钥位置：${NC}${key_path}"
    echo -e "  ${BLUE}公钥位置：${NC}${key_path}.pub"
    echo ""
    echo -e "  ${YELLOW}私钥内容（请妥善保管，仅显示一次）：${NC}"
    echo ""
    cat "$key_path"
    echo ""
    echo -e "  ${GREEN}公钥内容（已自动添加到 authorized_keys）：${NC}"
    cat "${key_path}.pub"
    echo ""

    sep
}

#-------------------- 功能 7：粘贴公钥 --------------------
paste_public_key() {
    sep
    echo -e "${BOLD}              添加公钥（粘贴）${NC}"
    sep
    echo ""

    # 选择用户
    echo -e "  ${BOLD}为哪个用户添加公钥？${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} root"
    echo -e "  ${CYAN} 2)${NC} 当前用户 ($(whoami))"
    echo -e "  ${CYAN} 3)${NC} 指定其他用户"
    echo ""
    echo -n "请选择 [1/2/3]（默认 1）: "
    read -r user_choice

    local target_user="root"
    local target_home="/root"

    case "$user_choice" in
        2)
            target_user=$(whoami)
            target_home=$(eval echo "~$target_user")
            ;;
        3)
            echo -n "  输入用户名: "
            read -r target_user
            target_home=$(eval echo "~$target_user")
            ;;
    esac

    local ssh_dir="${target_home}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    # 创建目录
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    touch "$auth_keys"
    chmod 600 "$auth_keys"
    chown -R "$target_user:$target_user" "$ssh_dir" 2>/dev/null

    echo ""
    echo -e "  ${BOLD}选择输入方式：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 粘贴公钥（手动输入，支持 ssh-rsa / ssh-ed25519 / ecdsa）"
    echo -e "  ${CYAN} 2)${NC} 从文件导入（服务器上的文件路径）"
    echo -e "  ${CYAN} 3)${NC} 从 GitHub 导入（输入 GitHub 用户名）"
    echo ""
    echo -n "请选择 [1/2/3]（默认 1）: "
    read -r input_method

    case "$input_method" in
        2)
            echo ""
            echo -n "  输入公钥文件路径（如 /tmp/id_rsa.pub）: "
            read -r key_file
            if [[ -f "$key_file" ]]; then
                local pub_key=$(cat "$key_file")
                echo ""
                echo -e "  ${BLUE}公钥内容：${NC}"
                echo -e "  ${CYAN}${pub_key}${NC}"
                echo ""
                echo "$pub_key" >> "$auth_keys"
                ok "公钥已添加到 ${auth_keys}"
            else
                error "文件不存在: $key_file"
            fi
            ;;
        3)
            echo ""
            echo -n "  输入 GitHub 用户名: "
            read -r github_user
            echo ""
            info "从 GitHub 获取公钥..."
            local gh_keys=$(curl -s "https://github.com/${github_user}.keys" 2>/dev/null)
            if [[ -n "$gh_keys" ]]; then
                echo -e "  ${BLUE}找到以下公钥：${NC}"
                echo "$gh_keys" | head -10 | nl -ba | while read -r num key; do
                    echo -e "  ${CYAN}[${num}]${NC} ${key:0:60}..."
                done
                local key_count=$(echo "$gh_keys" | wc -l)
                echo ""
                echo -e "  共 ${key_count} 个公钥"
                echo -n "  添加全部？(Y/n): "
                read -r add_all
                if [[ ! "$add_all" =~ ^[Nn]$ ]]; then
                    echo "$gh_keys" >> "$auth_keys"
                    ok "已添加 ${key_count} 个公钥到 ${auth_keys}"
                fi
            else
                error "未找到 GitHub 用户 ${github_user} 的公钥"
            fi
            ;;
        *)
            echo ""
            echo -e "  ${YELLOW}请粘贴公钥内容（支持多行，粘贴完成后按 Enter 输入单独的 END 结束）：${NC}"
            echo ""
            echo -e "  ${CYAN}──────── 公钥开始 ────────${NC}"

            local key_content=""
            while IFS= read -r line; do
                if [[ "$line" == "END" ]]; then
                    break
                fi
                key_content+="${line}"$'\n'
            done

            echo -e "  ${CYAN}──────── 公钥结束 ────────${NC}"
            echo ""

            # 验证公钥格式
            if echo "$key_content" | grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|sk-ssh-ed25519|sk-ecdsa)"; then
                echo "$key_content" >> "$auth_keys"
                ok "公钥已添加到 ${auth_keys}"
            else
                error "公钥格式不正确！正确的公钥以 ssh-rsa / ssh-ed25519 / ecdsa 开头"
                echo -e "  ${YELLOW}请检查并重新粘贴${NC}"
                return
            fi
            ;;
    esac

    # 修复权限
    chmod 600 "$auth_keys"
    chown "$target_user:$target_user" "$auth_keys" 2>/dev/null

    echo ""
    echo -e "  ${GREEN}${BOLD}● 公钥添加成功！${NC}"
    echo -e "  ${BLUE}目标用户：${NC}${target_user}"
    echo -e "  ${BLUE}授权文件：${NC}${auth_keys}"

    sep
}

#-------------------- 功能 8：管理已授权密钥 --------------------
manage_keys() {
    sep
    echo -e "${BOLD}              管理已授权密钥${NC}"
    sep
    echo ""

    # 选择用户
    echo -n "  查看哪个用户的密钥？(默认 root): "
    read -r target_user
    target_user="${target_user:-root}"
    local target_home=$(eval echo "~$target_user")
    local auth_keys="${target_home}/.ssh/authorized_keys"

    if [[ ! -f "$auth_keys" ]]; then
        warn "用户 ${target_user} 没有授权密钥文件"
        sep
        return
    fi

    local key_count=$(grep -c -E "^(ssh-rsa|ssh-ed25519|ecdsa|sk-)" "$auth_keys" 2>/dev/null || echo 0)
    echo -e "  ${BLUE}用户：${NC}${target_user}"
    echo -e "  ${BLUE}密钥数量：${NC}${key_count}"
    echo ""

    if [[ "$key_count" -eq 0 ]]; then
        warn "暂无已授权密钥"
        sep
        return
    fi

    echo -e "  ${BOLD}已授权密钥列表：${NC}"
    local idx=1
    declare -A key_map
    declare -A key_line_map

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local key_type=$(echo "$line" | awk '{print $1}')
        local comment=$(echo "$line" | awk '{$1="";$2="";print substr($0,3)}')
        [[ -z "$comment" ]] && comment="(无备注)"
        local display="${comment:0:50}"
        echo -e "  ${CYAN}[$idx]${NC} ${key_type} ${display}"
        key_map[$idx]="$line"
        key_line_map[$idx]=$(grep -n "^${key_type}" "$auth_keys" | head -1 | cut -d: -f1)
        idx=$((idx + 1))
    done < <(grep -E "^(ssh-rsa|ssh-ed25519|ecdsa|sk-)" "$auth_keys")

    echo ""
    echo -e "  ${CYAN} 1)${NC} 删除指定密钥"
    echo -e "  ${CYAN} 2)${NC} 清空所有密钥"
    echo -e "  ${CYAN} 3)${NC} 查看完整密钥内容"
    echo -e "  ${CYAN} 0)${NC} 返回"
    echo ""
    echo -n "请选择: "
    read -r action

    case "$action" in
        1)
            echo ""
            echo -n "  输入要删除的密钥编号: "
            read -r del_idx
            if [[ -n "${key_line_map[$del_idx]}" ]]; then
                local del_line="${key_line_map[$del_idx]}"
                sed -i "${del_line}d" "$auth_keys"
                ok "密钥 [$del_idx] 已删除"
            else
                warn "无效编号"
            fi
            ;;
        2)
            echo ""
            warn "此操作将清空所有已授权密钥！"
            echo -n "  确认？输入 YES: "
            read -r confirm
            if [[ "$confirm" == "YES" ]]; then
                > "$auth_keys"
                ok "所有密钥已清空"
            fi
            ;;
        3)
            echo ""
            echo -e "  ${BOLD}完整 authorized_keys 内容：${NC}"
            cat -n "$auth_keys" | while read -r line; do
                echo -e "  ${CYAN}${line}${NC}"
            done
            ;;
    esac

    sep
}

#-------------------- 功能 9：启用密钥 & 禁用密码 --------------------
toggle_auth() {
    sep
    echo -e "${BOLD}              启用密钥登录 & 禁用密码登录${NC}"
    sep
    echo ""

    local pubkey=$(get_ssh_config "PubkeyAuthentication")
    local passauth=$(get_ssh_config "PasswordAuthentication")

    echo -e "  ${BLUE}当前密钥认证：${NC}${pubkey:-未设置}"
    echo -e "  ${BLUE}当前密码认证：${NC}${passauth:-未设置}"
    echo ""

    warn "关闭密码登录前，请确保已添加公钥到 authorized_keys！"
    warn "否则将无法 SSH 登录服务器！"
    echo ""

    # 1. 启用密钥认证
    info "启用密钥认证..."
    set_ssh_config "PubkeyAuthentication" "yes"
    ok "PubkeyAuthentication = yes"

    # 2. 禁用密码认证
    echo ""
    echo -n "  确认禁用密码登录？(输入 YES 确认): "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        warn "已取消密码登录禁用"
        return
    fi

    set_ssh_config "PasswordAuthentication" "no"
    set_ssh_config "ChallengeResponseAuthentication" "no"
    set_ssh_config "KbdInteractiveAuthentication" "no"
    ok "PasswordAuthentication = no"

    # 3. Root 仅允许密钥登录
    echo ""
    set_ssh_config "PermitRootLogin" "prohibit-password"
    ok "PermitRootLogin = prohibit-password"

    # 验证配置语法
    echo ""
    info "验证配置语法..."
    if sshd -t 2>/dev/null; then
        ok "配置语法正确"
    else
        error "配置语法错误！"
        return
    fi

    restart_sshd

    echo ""
    echo -e "  ${GREEN}${BOLD}● 密钥登录已启用，密码登录已禁用${NC}"
    echo ""
    warn "请确保本地已配置密钥并在新终端测试连接"
    warn "如果无法连接，请通过 VNC/控制台 恢复："
    echo -e "    ${CYAN}sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' ${SSHD_CONFIG}${NC}"
    echo -e "    ${CYAN}sudo systemctl restart sshd${NC}"

    sep
}

#-------------------- 功能 10：配置摘要 --------------------
show_config_summary() {
    sep
    echo -e "${BOLD}              SSH 配置摘要${NC}"
    sep
    echo ""

    if [[ ! -f "$SSHD_CONFIG" ]]; then
        error "SSH 配置文件不存在"
        return
    fi

    local params=(
        "Port:SSH 端口"
        "ListenAddress:监听地址"
        "PermitRootLogin:Root 登录"
        "PubkeyAuthentication:密钥认证"
        "PasswordAuthentication:密码认证"
        "PermitEmptyPasswords:空密码"
        "MaxAuthTries:最大认证次数"
        "ClientAliveInterval:心跳间隔"
        "ClientAliveCountMax:心跳次数"
        "UseDNS:DNS 反查"
        "X11Forwarding:X11 转发"
        "AllowUsers:允许用户"
        "AllowGroups:允许组"
        "DenyUsers:拒绝用户"
        "IgnoreRhosts:忽略 Rhosts"
    )

    echo -e "  ${BOLD}配置项                    值${NC}"
    sep_s

    for item in "${params[@]}"; do
        local key="${item%%:*}"
        local desc="${item##*:}"
        local value=$(get_ssh_config "$key")
        if [[ -n "$value" ]]; then
            # 格式化输出
            printf "  %-25s ${CYAN}%s${NC}\n" "$desc" "$value"
        fi
    done

    echo ""
    sep_s
    echo ""
    echo -e "  ${BOLD}授权密钥文件：${NC}"
    for user_home in /root $(eval echo "~$(whoami)"); do
        local ak="${user_home}/.ssh/authorized_keys"
        if [[ -f "$ak" ]]; then
            local count=$(grep -cE "^(ssh-rsa|ssh-ed25519|ecdsa)" "$ak" 2>/dev/null || echo 0)
            echo -e "    ${CYAN}${ak}${NC} (${count} 个密钥)"
        fi
    done

    echo ""
    echo -e "  ${BOLD}SSH 服务状态：${NC}"
    local sshd_active=$(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null)
    echo -e "    服务状态: ${CYAN}${sshd_active:-未知}${NC}"
    local sshd_port=$(get_current_port)
    echo -e "    监听端口: ${CYAN}${sshd_port:-22}${NC}"

    sep
}

#-------------------- 功能 11：恢复备份 --------------------
restore_config() {
    sep
    echo -e "${BOLD}              恢复 SSH 配置备份${NC}"
    sep
    echo ""

    # 查找备份
    local backups=$(ls -t /etc/ssh/sshd_config.backup.* 2>/dev/null)

    if [[ -z "$backups" ]]; then
        warn "未找到 SSH 配置备份"
        sep
        return
    fi

    echo -e "  ${BOLD}可用备份：${NC}"
    echo ""
    local idx=1
    declare -A bak_map

    while read -r bak; do
        [[ -f "$bak" ]] || continue
        local bak_name=$(basename "$bak")
        local bak_date=$(echo "$bak_name" | grep -oP '\d{8}_\d{6}')
        echo -e "  ${CYAN}[$idx]${NC} ${bak_name}"
        bak_map[$idx]="$bak"
        idx=$((idx + 1))
    done <<< "$backups"

    echo ""
    echo -n "  输入要恢复的备份编号: "
    read -r restore_idx

    if [[ -z "$restore_idx" || -z "${bak_map[$restore_idx]}" ]]; then
        warn "无效选择"
        return
    fi

    local source="${bak_map[$restore_idx]}"

    warn "恢复将覆盖当前 SSH 配置！"
    echo -n "  确认恢复？(输入 YES): "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    # 备份当前
    cp "$SSHD_CONFIG" "/etc/ssh/sshd_config.pre_restore.$(date +%Y%m%d_%H%M%S)"

    # 恢复
    cp "$source" "$SSHD_CONFIG"
    ok "已恢复备份: $(basename $source)"

    # 验证
    if sshd -t 2>/dev/null; then
        ok "配置语法正确"
        restart_sshd
        echo ""
        echo -e "  ${GREEN}${BOLD}● SSH 配置已恢复！${NC}"
    else
        error "恢复的配置语法错误，请手动检查！"
    fi

    sep
}

#-------------------- 主循环 --------------------
main() {
    check_root
    check_sshd

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1)  change_port ;;
            2)  security_hardening ;;
            3)  install_fail2ban ;;
            4)  fail2ban_status ;;
            5)  ssh_login_log ;;
            6)  generate_key ;;
            7)  paste_public_key ;;
            8)  manage_keys ;;
            9)  toggle_auth ;;
            10) show_config_summary ;;
            11) restore_config ;;
            0|q|Q)
                echo ""
                info "退出 SSH 安全管理脚本"
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
