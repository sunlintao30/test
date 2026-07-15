#!/bin/bash
#=============================================================================
# 1Panel 面板一键安装与管理脚本
# 功能：安装/配置/管理 1Panel Linux 服务器运维面板
# 支持：Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora / openEuler
# 用法：chmod +x 1panel_manager.sh && sudo ./1panel_manager.sh
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
INSTALL_DIR="/opt/1panel"
BACKUP_DIR="/opt/1panel_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

#-------------------- 获取系统信息 --------------------
get_system_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_NAME="${PRETTY_NAME}"
        OS_VERSION="${VERSION_ID}"
    else
        OS_NAME="未知系统"
    fi

    OS_ARCH=$(uname -m)
    OS_MEM=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
    OS_CPU=$(nproc 2>/dev/null || echo "未知")
}

#-------------------- 检查 1Panel 状态 --------------------
check_1panel_status() {
    if [[ -f /usr/local/bin/1pctl ]]; then
        1PANEL_INSTALLED=true
    else
        1PANEL_INSTALLED=false
    fi

    if systemctl is-active --quiet 1panel 2>/dev/null; then
        1PANEL_RUNNING=true
    else
        1PANEL_RUNNING=false
    fi
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    get_system_info
    check_1panel_status

    sep
    echo -e "${BOLD}          1Panel 面板一键安装与管理${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}系统信息：${NC}${OS_NAME}"
    echo -e "  ${BLUE}架构    ：${NC}${OS_ARCH}  |  ${BLUE}内存：${NC}${OS_MEM}MB  |  ${BLUE}CPU：${NC}${OS_CPU}核"
    echo ""

    if $1PANEL_INSTALLED; then
        if $1PANEL_RUNNING; then
            echo -e "  ${BLUE}面板状态：${NC}${GREEN}已安装并运行中${NC}"
        else
            echo -e "  ${BLUE}面板状态：${NC}${YELLOW}已安装但未运行${NC}"
        fi
        echo ""

        # 获取面板信息
        if $1PANEL_RUNNING; then
            1pctl user-info 2>/dev/null | while IFS= read -r line; do
                echo -e "  ${CYAN}${line}${NC}"
            done
            echo ""
        fi
    else
        echo -e "  ${BLUE}面板状态：${NC}${YELLOW}未安装${NC}"
        echo ""
    fi

    sep
    echo ""

    echo -e "  ${CYAN}【安装】${NC}"
    echo -e "  ${CYAN} 1)${NC} 一键安装 1Panel（官方最新版）"
    echo -e "  ${CYAN} 2)${NC} 一键安装 1Panel（自定义安装参数）"
    echo ""

    echo -e "  ${CYAN}【管理】${NC}"
    echo -e "  ${CYAN} 3)${NC} 查看面板信息（地址/端口/用户名/密码/入口）"
    echo -e "  ${CYAN} 4)${NC} 启动 1Panel"
    echo -e "  ${CYAN} 5)${NC} 停止 1Panel"
    echo -e "  ${CYAN} 6)${NC} 重启 1Panel"
    echo -e "  ${CYAN} 7)${NC} 查看运行状态"
    echo ""

    echo -e "  ${CYAN}【配置】${NC}"
    echo -e "  ${CYAN} 8)${NC} 重置面板密码"
    echo -e "  ${CYAN} 9)${NC} 修改面板端口"
    echo -e "  ${CYAN}10)${NC} 修改安全入口"
    echo -e "  ${CYAN}11)${NC} 查看面板日志"
    echo ""

    echo -e "  ${CYAN}【维护】${NC}"
    echo -e "  ${CYAN}12)${NC} 备份 1Panel 数据"
    echo -e "  ${CYAN}13)${NC} 恢复 1Panel 数据"
    echo -e "  ${CYAN}14)${NC} 更新 1Panel 到最新版"
    echo -e "  ${CYAN}15)${NC} 卸载 1Panel"
    echo -e "  ${CYAN} 0)${NC} 退出"
    echo ""
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：默认安装 --------------------
install_default() {
    sep
    echo -e "${BOLD}              一键安装 1Panel（官方最新版）${NC}"
    sep
    echo ""

    # 检查系统兼容性
    check_system_compatibility

    # 检查 Docker
    if ! command -v docker &>/dev/null; then
        info "Docker 未安装，将在安装过程中自动安装"
    else
        ok "Docker 已安装: $(docker --version)"
    fi

    echo ""
    echo -e "  ${BOLD}安装配置说明：${NC}"
    echo -e "  - 安装目录：${CYAN}${INSTALL_DIR}${NC}"
    echo -e "  - 面板端口：${CYAN}系统自动分配${NC}"
    echo -e "  - 安全入口：${CYAN}系统自动生成${NC}"
    echo -e "  - 用户名　：${CYAN}admin${NC}"
    echo -e "  - 密码　　：${CYAN}系统自动生成${NC}"
    echo ""

    echo -e "  ${YELLOW}注意：安装过程可能需要 5-10 分钟，请耐心等待${NC}"
    echo ""
    echo -n "  确认安装？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消安装"
        return
    fi

    echo ""
    echo -e "${BOLD}开始安装 1Panel...${NC}"
    echo ""

    # 执行官方安装脚本
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"

    echo ""
    info "安装完成！"
    echo ""
    echo -e "  ${GREEN}${BOLD}● 1Panel 安装成功！${NC}"
    echo ""
    echo -e "  ${YELLOW}请使用以下命令查看面板信息：${NC}"
    echo -e "  ${CYAN}1pctl user-info${NC}"
    echo ""

    sep
}

#-------------------- 功能 2：自定义安装 --------------------
install_custom() {
    sep
    echo -e "${BOLD}            自定义安装 1Panel${NC}"
    sep
    echo ""

    check_system_compatibility

    echo -e "  ${YELLOW}重要：安装后请勿手动修改以下配置，以免影响面板正常运行${NC}"
    echo ""

    # 安装目录
    echo -n "  安装目录（默认 /opt/1panel）: "
    read -r custom_dir
    INSTALL_DIR="${custom_dir:-/opt/1panel}"

    # 面板端口
    echo -n "  面板端口（默认随机，建议 10000-65535 范围）: "
    read -r custom_port
    if [[ -n "$custom_port" ]]; then
        if ! [[ "$custom_port" =~ ^[0-9]+$ ]] || [[ "$custom_port" -lt 1 ]] || [[ "$custom_port" -gt 65535 ]]; then
            error "无效端口号，将使用随机端口"
            custom_port=""
        fi
    fi

    # 面板用户名
    echo -n "  面板用户名（默认 admin）: "
    read -r custom_user
    CUSTOM_USER="${custom_user:-admin}"

    # 面板密码
    echo -n "  面板密码（留空自动生成，至少 8 位）: "
    read -r custom_pass
    if [[ -n "$custom_pass" ]]; then
        if [[ ${#custom_pass} -lt 8 ]]; then
            error "密码长度不足 8 位，将自动生成密码"
            custom_pass=""
        fi
    fi

    echo ""
    echo -e "  ${BOLD}安装配置汇总：${NC}"
    echo -e "  ${BLUE}安装目录：${NC}${INSTALL_DIR}"
    echo -e "  ${BLUE}面板端口：${NC}${custom_port:-自动分配}"
    echo -e "  ${BLUE}用户名  ：${NC}${CUSTOM_USER}"
    echo -e "  ${BLUE}密码    ：${NC}${custom_pass:-自动生成}"
    echo ""

    echo -n "  确认安装？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消安装"
        return
    fi

    echo ""
    echo -e "${BOLD}开始安装 1Panel...${NC}"
    echo ""

    # 构建安装命令
    local install_cmd="bash -c \"\$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)\""

    if [[ -n "$custom_port" ]]; then
        export PANEL_PORT="$custom_port"
    fi
    if [[ -n "$custom_user" ]]; then
        export PANEL_USERNAME="$custom_user"
    fi
    if [[ -n "$custom_pass" ]]; then
        export PANEL_PASSWORD="$custom_pass"
    fi
    export PANEL_BASE_DIR="$INSTALL_DIR"

    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"

    echo ""
    info "安装完成！"
    echo ""
    echo -e "  ${GREEN}${BOLD}● 1Panel 自定义安装成功！${NC}"
    echo ""

    sep
}

#-------------------- 系统兼容性检查 --------------------
check_system_compatibility() {
    echo -e "  ${BOLD}系统兼容性检查：${NC}"
    echo ""

    local ok_count=0
    local warn_count=0

    # 检查操作系统
    case "$OS_ID" in
        ubuntu|debian|centos|rhel|rocky|almalinux|fedora|openeuler|anolis|kylin|uos)
            ok "操作系统: ${OS_NAME}"
            ok_count=$((ok_count + 1))
            ;;
        *)
            warn "操作系统 ${OS_NAME} 未经过官方完整测试，但仍可尝试安装"
            warn_count=$((warn_count + 1))
            ;;
    esac

    # 检查架构
    case "$OS_ARCH" in
        x86_64|aarch64|armv7l|ppc64le|s390x|riscv64)
            ok "CPU 架构: ${OS_ARCH}"
            ok_count=$((ok_count + 1))
            ;;
        *)
            warn "CPU 架构 ${OS_ARCH} 可能不被支持"
            warn_count=$((warn_count + 1))
            ;;
    esac

    # 检查内存
    if [[ "$OS_MEM" -ge 2048 ]]; then
        ok "内存: ${OS_MEM}MB (充足)"
        ok_count=$((ok_count + 1))
    elif [[ "$OS_MEM" -ge 1024 ]]; then
        ok "内存: ${OS_MEM}MB (满足最低要求)"
        ok_count=$((ok_count + 1))
    else
        warn "内存: ${OS_MEM}MB (建议至少 1GB，可能影响使用体验)"
        warn_count=$((warn_count + 1))
    fi

    # 检查磁盘空间
    local disk_avail=$(df /opt 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ -n "$disk_avail" ]]; then
        local disk_gb=$(( disk_avail / 1024 / 1024 ))
        if [[ "$disk_gb" -ge 5 ]]; then
            ok "磁盘空间: 约 ${disk_gb}GB (充足)"
            ok_count=$((ok_count + 1))
        elif [[ "$disk_gb" -ge 2 ]]; then
            ok "磁盘空间: 约 ${disk_gb}GB (基本够用)"
            ok_count=$((ok_count + 1))
        else
            warn "磁盘空间: 约 ${disk_gb}GB (建议至少 2GB)"
            warn_count=$((warn_count + 1))
        fi
    fi

    # 检查 curl
    if command -v curl &>/dev/null; then
        ok "curl: 已安装"
        ok_count=$((ok_count + 1))
    else
        warn "curl 未安装，将自动安装"
        warn_count=$((warn_count + 1))
    fi

    echo ""

    if [[ "$warn_count" -gt 0 ]]; then
        echo -e "  ${YELLOW}存在 ${warn_count} 个警告项，建议修复后再安装${NC}"
        echo ""
        echo -n "  是否继续安装？(Y/n): "
        read -r continue_install
        if [[ "$continue_install" =~ ^[Nn]$ ]]; then
            info "已取消安装"
            exit 0
        fi
    else
        echo -e "  ${GREEN}${BOLD}所有检查项通过，可以安装！${NC}"
    fi

    echo ""
}

#-------------------- 功能 3：查看面板信息 --------------------
show_panel_info() {
    sep
    echo -e "${BOLD}              1Panel 面板信息${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        warn "1Panel 未安装"
        sep
        return
    fi

    if ! $1PANEL_RUNNING; then
        warn "1Panel 服务未运行，部分信息可能不完整"
        echo ""
    fi

    1pctl user-info 2>/dev/null || warn "无法获取面板信息，请确认 1Panel 已安装"

    echo ""

    # 获取更多信息
    if [[ -f /usr/local/bin/1pctl ]]; then
        echo -e "  ${BOLD}1Panel 版本信息：${NC}"
        1pctl version 2>/dev/null || echo -e "    ${YELLOW}无法获取版本${NC}"
    fi

    sep
}

#-------------------- 功能 4/5/6：启动/停止/重启 --------------------
start_1panel() {
    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    systemctl start 1panel
    ok "1Panel 已启动"
}

stop_1panel() {
    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    systemctl stop 1panel
    ok "1Panel 已停止"
}

restart_1panel() {
    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    systemctl restart 1panel
    ok "1Panel 已重启"
}

#-------------------- 功能 7：查看运行状态 --------------------
show_status() {
    sep
    echo -e "${BOLD}              1Panel 运行状态${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        warn "1Panel 未安装"
        sep
        return
    fi

    echo -e "  ${BOLD}服务状态：${NC}"
    systemctl status 1panel 2>/dev/null --no-pager -l | head -20 || warn "无法获取服务状态"
    echo ""

    echo -e "  ${BOLD}Docker 容器状态：${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -i "1panel" || echo -e "    ${YELLOW}无 1Panel 相关容器运行${NC}"

    sep
}

#-------------------- 功能 8：重置密码 --------------------
reset_password() {
    sep
    echo -e "${BOLD}              重置面板密码${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    echo -n "  输入新密码（至少 8 位，留空随机生成）: "
    read -r new_pass

    if [[ -n "$new_pass" ]]; then
        if [[ ${#new_pass} -lt 8 ]]; then
            error "密码长度不足 8 位"
            return
        fi
    fi

    echo ""
    echo -n "  确认重置密码？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    if [[ -n "$new_pass" ]]; then
        1pctl reset password "$new_pass"
    else
        1pctl reset password
    fi

    echo ""
    ok "密码已重置"
    echo ""
    echo -e "  ${YELLOW}新密码请通过以下命令查看：${NC}"
    echo -e "  ${CYAN}1pctl user-info${NC}"

    sep
}

#-------------------- 功能 9：修改端口 --------------------
change_port() {
    sep
    echo -e "${BOLD}              修改面板端口${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    echo -n "  输入新端口号（10000-65535）: "
    read -r new_port

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        error "无效端口号"
        return
    fi

    echo ""
    echo -n "  确认修改端口为 ${new_port}？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    1pctl set port "$new_port"

    echo ""
    ok "面板端口已修改为 ${new_port}"
    echo -e "  ${YELLOW}修改后需要重启面板才能生效${NC}"
    echo ""

    echo -n "  是否立即重启面板？(Y/n): "
    read -r restart_confirm
    if [[ ! "$restart_confirm" =~ ^[Nn]$ ]]; then
        systemctl restart 1panel
        ok "面板已重启"

        # 放行防火墙
        if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
            firewall-cmd --permanent --add-port="${new_port}/tcp" 2>/dev/null
            firewall-cmd --reload 2>/dev/null
            ok "firewalld 已开放端口 ${new_port}"
        fi
        if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
            ufw allow "${new_port}/tcp" 2>/dev/null
            ok "UFW 已开放端口 ${new_port}"
        fi
    fi

    sep
}

#-------------------- 功能 10：修改安全入口 --------------------
change_entrance() {
    sep
    echo -e "${BOLD}              修改安全入口${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    echo -e "  ${YELLOW}安全入口是 URL 中的路径前缀，用于增加面板安全性${NC}"
    echo -e "  ${YELLOW}示例：/panel-admin → http://IP:PORT/panel-admin/login${NC}"
    echo ""

    echo -n "  输入新安全入口（如 /my-panel，留空恢复默认）: "
    read -r new_entrance

    if [[ -z "$new_entrance" ]]; then
        warn "留空将恢复默认安全入口"
        echo ""
        echo -n "  确认恢复默认？(y/N): "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "已取消"
            return
        fi
    else
        echo ""
        echo -n "  确认修改安全入口为 ${new_entrance}？(y/N): "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "已取消"
            return
        fi
    fi

    if [[ -n "$new_entrance" ]]; then
        1pctl set entrance "$new_entrance"
    else
        1pctl reset entrance
    fi

    echo ""
    ok "安全入口已修改"
    echo -e "  ${YELLOW}修改后需要重启面板才能生效${NC}"
    echo ""

    echo -n "  是否立即重启面板？(Y/n): "
    read -r restart_confirm
    if [[ ! "$restart_confirm" =~ ^[Nn]$ ]]; then
        systemctl restart 1panel
        ok "面板已重启"
    fi

    sep
}

#-------------------- 功能 11：查看日志 --------------------
show_logs() {
    sep
    echo -e "${BOLD}              1Panel 面板日志${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    echo -e "  ${BOLD}最近 50 条日志：${NC}"
    echo ""
    journalctl -u 1panel --no-pager -n 50 2>/dev/null || warn "无法获取日志"

    echo ""
    echo -e "  ${YELLOW}提示：使用 journalctl -u 1panel -f 可实时查看日志${NC}"

    sep
}

#-------------------- 功能 12：备份数据 --------------------
backup_1panel() {
    sep
    echo -e "${BOLD}              备份 1Panel 数据${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    mkdir -p "$BACKUP_DIR"

    local backup_file="${BACKUP_DIR}/1panel_backup_${TIMESTAMP}.tar.gz"

    info "开始备份 1Panel 数据..."

    # 备份 1Panel 配置目录
    if [[ -d "$INSTALL_DIR" ]]; then
        info "备份安装目录: ${INSTALL_DIR}..."
        tar -czf "$backup_file" -C /opt 1panel 2>/dev/null || {
            warn "备份安装目录失败，尝试备份关键配置..."
            local temp_backup="${BACKUP_DIR}/1panel_${TIMESTAMP}"
            mkdir -p "$temp_backup"
            cp -r "$INSTALL_DIR"/* "$temp_backup/" 2>/dev/null
            tar -czf "$backup_file" -C "$temp_backup" . 2>/dev/null
            rm -rf "$temp_backup"
        }
    fi

    # 备份 systemd 服务
    if [[ -f /etc/systemd/system/1panel.service ]]; then
        cp /etc/systemd/system/1panel.service "${BACKUP_DIR}/1panel.service.${TIMESTAMP}"
    fi

    ok "备份完成"
    echo ""
    echo -e "  ${GREEN}${BOLD}● 备份文件：${NC}${backup_file}"
    echo -e "  ${BLUE}备份大小：${NC}$(du -h "$backup_file" | cut -f1)"
    echo -e "  ${BLUE}备份时间：${NC}$(date '+%Y-%m-%d %H:%M:%S')"

    sep
}

#-------------------- 功能 13：恢复数据 --------------------
restore_1panel() {
    sep
    echo -e "${BOLD}              恢复 1Panel 数据${NC}"
    sep
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "暂无备份文件"
        sep
        return
    fi

    echo -e "  ${YELLOW}可用备份文件：${NC}"
    echo ""

    local idx=1
    declare -A backup_map

    # 按时间倒序列出备份文件
    for f in $(ls -t "${BACKUP_DIR}"/1panel_backup_*.tar.gz 2>/dev/null); do
        [[ -f "$f" ]] || continue
        local fname=$(basename "$f")
        local fsize=$(du -h "$f" | cut -f1)
        local ftime=$(echo "$fname" | sed 's/1panel_backup_//' | sed 's/\.tar\.gz//')
        echo -e "  ${CYAN}[$idx]${NC} ${fname}"
        echo -e "       大小: ${fsize}  |  时间: ${ftime}"
        echo ""
        backup_map[$idx]="$f"
        idx=$((idx + 1))
    done

    echo -n "  输入要恢复的备份编号（或 Enter 取消）: "
    read -r restore_idx

    if [[ -z "$restore_idx" || -z "${backup_map[$restore_idx]}" ]]; then
        info "已取消"
        return
    fi

    local source="${backup_map[$restore_idx]}"

    warn "恢复操作将覆盖当前 1Panel 数据，请谨慎操作！"
    echo -e "  ${RED}此操作不可撤销！${NC}"
    echo ""
    echo -n "  确认恢复？请输入 'YES' 确认: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    # 停止服务
    if $1PANEL_RUNNING; then
        info "停止 1Panel 服务..."
        systemctl stop 1panel
    fi

    # 备份当前数据
    local current_backup="${BACKUP_DIR}/1panel_backup_before_restore_${TIMESTAMP}.tar.gz"
    if [[ -d "$INSTALL_DIR" ]]; then
        tar -czf "$current_backup" -C /opt 1panel 2>/dev/null
        ok "当前数据已备份到: ${current_backup}"
    fi

    echo ""

    # 恢复
    info "恢复数据..."
    rm -rf "$INSTALL_DIR"/* 2>/dev/null
    tar -xzf "$source" -C /opt/ 2>/dev/null

    ok "数据已恢复"

    # 启动服务
    info "启动 1Panel 服务..."
    systemctl start 1panel

    echo ""
    echo -e "  ${GREEN}${BOLD}● 恢复完成！${NC}"

    sep
}

#-------------------- 功能 14：更新 1Panel --------------------
update_1panel() {
    sep
    echo -e "${BOLD}              更新 1Panel 到最新版${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    echo -e "  ${BLUE}当前版本：${NC}"
    1pctl version 2>/dev/null || echo "    未知"
    echo ""

    echo -n "  确认更新到最新版本？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "正在更新 1Panel..."
    1pctl update

    echo ""
    ok "更新完成"
    echo ""
    echo -e "  ${BLUE}新版本：${NC}"
    1pctl version 2>/dev/null

    sep
}

#-------------------- 功能 15：卸载 1Panel --------------------
uninstall_1panel() {
    sep
    echo -e "${BOLD}              卸载 1Panel${NC}"
    sep
    echo ""

    if ! $1PANEL_INSTALLED; then
        error "1Panel 未安装"
        return
    fi

    warn "卸载将删除 1Panel 及其所有数据！"
    echo -e "  ${RED}包括：面板配置、Docker 容器、安装的应用等${NC}"
    echo ""

    echo -e "  ${YELLOW}建议先备份数据（菜单选项 12）${NC}"
    echo ""

    echo -n "  确认卸载 1Panel？请输入 'YES' 确认: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    echo ""
    echo ""
    echo -n "  同时删除 Docker 及其数据？(y/N): "
    read -r remove_docker

    echo ""
    info "正在卸载 1Panel..."

    if command -v 1pctl &>/dev/null; then
        1pctl uninstall
    else
        warn "1pctl 命令未找到，手动清理..."
        systemctl stop 1panel 2>/dev/null
        systemctl disable 1panel 2>/dev/null
        rm -f /etc/systemd/system/1panel.service
        systemctl daemon-reload
        rm -rf "$INSTALL_DIR"
    fi

    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        warn "删除 Docker 数据..."
        docker stop $(docker ps -aq) 2>/dev/null
        docker rm $(docker ps -aq) 2>/dev/null
        docker rmi $(docker images -q) 2>/dev/null
        systemctl stop docker 2>/dev/null
        systemctl disable docker 2>/dev/null
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}● 1Panel 已卸载！${NC}"
    echo -e "  ${BLUE}备份文件保留在：${NC}${BACKUP_DIR}"

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
            1) install_default ;;
            2) install_custom ;;
            3) show_panel_info ;;
            4) start_1panel ;;
            5) stop_1panel ;;
            6) restart_1panel ;;
            7) show_status ;;
            8) reset_password ;;
            9) change_port ;;
            10) change_entrance ;;
            11) show_logs ;;
            12) backup_1panel ;;
            13) restore_1panel ;;
            14) update_1panel ;;
            15) uninstall_1panel ;;
            0|q|Q)
                echo ""
                info "退出 1Panel 管理脚本"
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