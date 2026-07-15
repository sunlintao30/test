#!/bin/bash
#=============================================================================
# 文件共享服务器管理脚本（多协议）
# 功能：SMB/CIFS / NFS / FTP / WebDAV / SFTP 一键安装与管理
# 支持：Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora
# 用法：chmod +x file_share.sh && sudo ./file_share.sh
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
SHARE_DIR="/srv/share"
CONFIG_BACKUP_DIR="/opt/share_backups"

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

#-------------------- 检测服务状态 --------------------
check_services() {
    SMB_STATUS="未安装"
    NFS_STATUS="未安装"
    FTP_STATUS="未安装"
    WEBDAV_STATUS="未安装"
    SFTP_STATUS="未安装"

    systemctl is-active --quiet smbd 2>/dev/null || systemctl is-active --quiet smb 2>/dev/null && SMB_STATUS="运行中"
    [[ -f /etc/samba/smb.conf ]] && [[ "$SMB_STATUS" == "未安装" ]] && SMB_STATUS="已安装未运行"

    systemctl is-active --quiet nfs-server 2>/dev/null || systemctl is-active --quiet nfs-kernel-server 2>/dev/null && NFS_STATUS="运行中"
    [[ -f /etc/exports ]] && [[ "$NFS_STATUS" == "未安装" ]] && NFS_STATUS="已安装未运行"

    systemctl is-active --quiet vsftpd 2>/dev/null && FTP_STATUS="运行中"
    [[ -f /etc/vsftpd.conf ]] || [[ -f /etc/vsftpd/vsftpd.conf ]] && [[ "$FTP_STATUS" == "未安装" ]] && FTP_STATUS="已安装未运行"

    systemctl is-active --quiet webdav 2>/dev/null || systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet nginx 2>/dev/null && WEBDAV_STATUS="运行中"
    [[ -f /etc/nginx/conf.d/webdav.conf ]] || [[ -f /etc/apache2/conf-enabled/webdav.conf ]] && [[ "$WEBDAV_STATUS" == "未安装" ]] && WEBDAV_STATUS="已安装未运行"

    systemctl is-active --quiet sshd 2>/dev/null && SFTP_STATUS="运行中" || SFTP_STATUS="未运行"
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    get_system_info
    check_services

    sep
    echo -e "${BOLD}        文件共享服务器管理（多协议）${NC}"
    sep
    echo ""

    echo -e "  ${BLUE}系统：${NC}${OS_NAME}"
    echo -e "  ${BLUE}共享目录：${NC}${SHARE_DIR}"
    echo ""

    echo -e "  ${BOLD}协议状态：${NC}"
    echo -e "  ${CYAN}SMB/CIFS ${NC} ${GREEN}${SMB_STATUS}${NC}    ${CYAN}NFS      ${NC} ${GREEN}${NFS_STATUS}${NC}"
    echo -e "  ${CYAN}FTP      ${NC} ${GREEN}${FTP_STATUS}${NC}    ${CYAN}WebDAV   ${NC} ${GREEN}${WEBDAV_STATUS}${NC}"
    echo -e "  ${CYAN}SFTP     ${NC} ${GREEN}${SFTP_STATUS}${NC}"
    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【SMB/CIFS 共享】${NC}"
    echo -e "  ${CYAN} 1)${NC} 安装并配置 Samba 共享"
    echo -e "  ${CYAN} 2)${NC} 管理 Samba 用户（添加/删除/改密）"
    echo -e "  ${CYAN} 3)${NC} 管理 Samba 共享目录（添加/删除）"
    echo -e "  ${CYAN} 4)${NC} 启动/停止/重启 Samba"
    echo ""

    echo -e "  ${CYAN}【NFS 共享】${NC}"
    echo -e "  ${CYAN} 5)${NC} 安装并配置 NFS 共享"
    echo -e "  ${CYAN} 6)${NC} 管理 NFS 共享目录（添加/删除）"
    echo -e "  ${CYAN} 7)${NC} 启动/停止/重启 NFS"
    echo ""

    echo -e "  ${CYAN}【FTP 共享】${NC}"
    echo -e "  ${CYAN} 8)${NC} 安装并配置 vsftpd（FTP 服务器）"
    echo -e "  ${CYAN} 9)${NC} 管理 FTP 用户"
    echo -e "  ${CYAN}10)${NC} 启动/停止/重启 FTP"
    echo ""

    echo -e "  ${CYAN}【WebDAV 共享】${NC}"
    echo -e "  ${CYAN}11)${NC} 安装并配置 WebDAV（Nginx）"
    echo -e "  ${CYAN}12)${NC} 管理 WebDAV 用户"
    echo -e "  ${CYAN}13)${NC} 启动/停止/重启 WebDAV"
    echo ""

    echo -e "  ${CYAN}【SFTP 共享】${NC}"
    echo -e "  ${CYAN}14)${NC} 配置 SFTP（基于 SSH）"
    echo -e "  ${CYAN}15)${NC} 管理 SFTP 用户（chroot 隔离）"
    echo ""

    echo -e "  ${CYAN}【综合管理】${NC}"
    echo -e "  ${CYAN}16)${NC} 一键部署全部协议"
    echo -e "  ${CYAN}17)${NC} 查看所有共享状态"
    echo -e "  ${CYAN}18)${NC} 防火墙配置（一键放行共享端口）"
    echo -e "  ${CYAN}19)${NC} 查看共享连接日志"
    echo -e "  ${CYAN} 0)${NC} 退出"
    echo ""
    sep
    echo -n "请输入选项: "
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

#-------------------- 创建共享目录 --------------------
create_share_dir() {
    local dir="${1:-$SHARE_DIR}"
    mkdir -p "$dir"
    chmod 755 "$dir"
    echo "$dir"
}

#=============================================================================
#                           SMB/CIFS 共享
#=============================================================================

#-------------------- 功能 1：安装配置 Samba --------------------
install_samba() {
    sep
    echo -e "${BOLD}          安装并配置 Samba（SMB/CIFS）${NC}"
    sep
    echo ""

    info "安装 Samba..."
    pkg_install samba samba-common
    ok "Samba 安装完成"
    echo ""

    # 创建共享目录
    echo -n "  共享目录路径（默认 ${SHARE_DIR}）: "
    read -r smb_dir
    smb_dir="${smb_dir:-$SHARE_DIR}"
    create_share_dir "$smb_dir"
    ok "共享目录已创建: ${smb_dir}"

    echo ""

    # 配置选项
    echo -e "  ${BOLD}共享配置：${NC}"
    echo -n "  共享名称（默认 share）: "
    read -r share_name
    share_name="${share_name:-share}"

    echo -n "  是否允许匿名访问？(y/N): "
    read -r guest_ok

    echo -n "  是否可写？(Y/n): "
    read -r writable
    writable=$( [[ "$writable" =~ ^[Nn]$ ]] && echo "no" || echo "yes" )

    echo ""

    # 创建 Samba 用户
    if [[ ! "$guest_ok" =~ ^[Yy]$ ]]; then
        echo -e "  ${BOLD}创建 Samba 用户：${NC}"
        echo -n "  用户名（必须已存在于系统中）: "
        read -r smb_user

        if id "$smb_user" &>/dev/null; then
            smbpasswd -a "$smb_user"
            ok "Samba 用户 ${smb_user} 已创建"
        else
            warn "系统用户 ${smb_user} 不存在"
            echo -n "  是否创建该系统用户？(y/N): "
            read -r create_user
            if [[ "$create_user" =~ ^[Yy]$ ]]; then
                useradd -m -s /bin/bash "$smb_user"
                passwd "$smb_user"
                smbpasswd -a "$smb_user"
                ok "系统用户和 Samba 用户 ${smb_user} 已创建"
            fi
        fi
    fi

    echo ""

    # 备份原配置
    [[ -f /etc/samba/smb.conf ]] && cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"

    # 写入配置
    info "写入 Samba 配置..."

    local guest_config=""
    if [[ "$guest_ok" =~ ^[Yy]$ ]]; then
        guest_config="guest ok = yes\n    force user = root"
    else
        guest_config="guest ok = no\n    valid users = ${smb_user:-root}"
    fi

    cat >> /etc/samba/smb.conf <<EOF

# ===== 共享: ${share_name} =====
[${share_name}]
    path = ${smb_dir}
    browseable = yes
    writable = ${writable}
    ${guest_config}
    create mask = 0664
    directory mask = 0775
EOF

    ok "配置已写入 /etc/samba/smb.conf"

    # 启动服务
    echo ""
    info "启动 Samba 服务..."
    if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
        systemctl enable smbd nmbd 2>/dev/null
        systemctl restart smbd nmbd 2>/dev/null
    else
        systemctl enable smb nmb 2>/dev/null
        systemctl restart smb nmb 2>/dev/null
    fi

    # 防火墙
    open_firewall_port 445
    open_firewall_port 139

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● Samba 共享已配置！${NC}"
    echo -e "  ${BLUE}共享名称：${NC}${share_name}"
    echo -e "  ${BLUE}共享路径：${NC}${smb_dir}"
    echo -e "  ${BLUE}可写    ：${NC}${writable}"
    echo -e "  ${BLUE}匿名访问：${NC}$([[ "$guest_ok" =~ ^[Yy]$ ]] && echo "是" || echo "否")"
    echo -e "  ${BLUE}访问地址：${NC}\\\\${server_ip}\\${share_name}"
    echo ""
    echo -e "  ${YELLOW}客户端访问方式：${NC}"
    echo -e "  ${CYAN}Windows: \\\\${server_ip}\\${share_name}${NC}"
    echo -e "  ${CYAN}Linux:   mount -t cifs //${server_ip}/${share_name} /mnt -o username=${smb_user:-guest}${NC}"
    echo -e "  ${CYAN}macOS:   smb://${server_ip}/${share_name}${NC}"

    sep
}

#-------------------- 功能 2：管理 Samba 用户 --------------------
manage_smb_users() {
    sep
    echo -e "${BOLD}          管理 Samba 用户${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 添加 Samba 用户"
    echo -e "  ${CYAN} 2)${NC} 修改 Samba 密码"
    echo -e "  ${CYAN} 3)${NC} 启用 Samba 用户"
    echo -e "  ${CYAN} 4)${NC} 禁用 Samba 用户"
    echo -e "  ${CYAN} 5)${NC} 删除 Samba 用户"
    echo -e "  ${CYAN} 6)${NC} 查看所有 Samba 用户"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  系统用户名: "
            read -r username
            if ! id "$username" &>/dev/null; then
                warn "用户 ${username} 不存在，正在创建..."
                useradd -m -s /bin/bash "$username"
                passwd "$username"
            fi
            smbpasswd -a "$username"
            ok "Samba 用户 ${username} 已添加"
            ;;
        2)
            echo -n "  用户名: "
            read -r username
            smbpasswd "$username"
            ok "密码已修改"
            ;;
        3)
            echo -n "  用户名: "
            read -r username
            smbpasswd -e "$username"
            ok "用户 ${username} 已启用"
            ;;
        4)
            echo -n "  用户名: "
            read -r username
            smbpasswd -d "$username"
            ok "用户 ${username} 已禁用"
            ;;
        5)
            echo -n "  用户名: "
            read -r username
            smbpasswd -x "$username"
            ok "Samba 用户 ${username} 已删除"
            ;;
        6)
            echo ""
            pdbedit -L -v 2>/dev/null | grep -E "Unix username|Account Flags" || warn "无法获取用户列表"
            ;;
    esac
    sep
}

#-------------------- 功能 3：管理 Samba 共享目录 --------------------
manage_smb_shares() {
    sep
    echo -e "${BOLD}          管理 Samba 共享目录${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}当前共享：${NC}"
    echo ""
    awk '/^\[/ && !/^\[global\]/ && !/^\[homes\]/ && !/^\[printers\]/ {print "  " $0}' /etc/samba/smb.conf 2>/dev/null || warn "无共享"
    echo ""

    echo -e "  ${CYAN} 1)${NC} 添加共享目录"
    echo -e "  ${CYAN} 2)${NC} 删除共享目录"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  共享名称: "
            read -r share_name
            echo -n "  共享路径: "
            read -r share_path
            mkdir -p "$share_path"
            chmod 755 "$share_path"

            echo -n "  可写？(Y/n): "
            read -r writable
            writable=$( [[ "$writable" =~ ^[Nn]$ ]] && echo "no" || echo "yes" )

            echo -n "  允许匿名？(y/N): "
            read -r guest_ok
            local guest_setting="guest ok = no"
            [[ "$guest_ok" =~ ^[Yy]$ ]] && guest_setting="guest ok = yes"

            cat >> /etc/samba/smb.conf <<EOF

[${share_name}]
    path = ${share_path}
    browseable = yes
    writable = ${writable}
    ${guest_setting}
    create mask = 0664
    directory mask = 0775
EOF
            ok "共享 ${share_name} 已添加"
            systemctl restart smbd smb 2>/dev/null || true
            ;;
        2)
            echo -n "  要删除的共享名称: "
            read -r share_name
            sed -i "/^\[${share_name}\]/,/^\[/ { /^\[${share_name}\]/d; /^\[/!d; }" /etc/samba/smb.conf 2>/dev/null
            ok "共享 ${share_name} 已删除"
            systemctl restart smbd smb 2>/dev/null || true
            ;;
    esac
    sep
}

#-------------------- 功能 4：Samba 服务控制 --------------------
control_samba() {
    sep
    echo -e "${BOLD}          Samba 服务控制${NC}"
    sep
    echo ""

    local svc_name="smbd"
    [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]] && svc_name="smb"

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start "$svc_name" nmb 2>/dev/null || systemctl start smbd nmbd 2>/dev/null; ok "已启动" ;;
        2) systemctl stop "$svc_name" nmb 2>/dev/null || systemctl stop smbd nmbd 2>/dev/null; ok "已停止" ;;
        3) systemctl restart "$svc_name" nmb 2>/dev/null || systemctl restart smbd nmbd 2>/dev/null; ok "已重启" ;;
        4) systemctl status "$svc_name" --no-pager -l 2>/dev/null || systemctl status smbd --no-pager -l 2>/dev/null ;;
    esac
    sep
}

#=============================================================================
#                           NFS 共享
#=============================================================================

#-------------------- 功能 5：安装配置 NFS --------------------
install_nfs() {
    sep
    echo -e "${BOLD}          安装并配置 NFS${NC}"
    sep
    echo ""

    info "安装 NFS..."
    case "$OS_ID" in
        ubuntu|debian)
            pkg_install nfs-kernel-server nfs-common
            ;;
        *)
            pkg_install nfs-utils
            ;;
    esac
    ok "NFS 安装完成"
    echo ""

    echo -n "  共享目录路径（默认 ${SHARE_DIR}）: "
    read -r nfs_dir
    nfs_dir="${nfs_dir:-$SHARE_DIR}"
    create_share_dir "$nfs_dir"

    echo -n "  允许访问的客户端（如 192.168.1.0/24，* 表示全部）: "
    read -r nfs_client
    nfs_client="${nfs_client:-*}"

    echo -e "  ${BOLD}权限选项：${NC}"
    echo -e "  ${CYAN} 1)${NC} 只读（ro）"
    echo -e "  ${CYAN} 2)${NC} 读写（rw）${GREEN}（推荐）${NC}"
    echo -n "请选择 [1-2]（默认 2）: "
    read -r perm_choice
    local perm="rw"
    [[ "$perm_choice" == "1" ]] && perm="ro"

    echo ""
    info "写入 NFS 配置..."

    # 备份
    [[ -f /etc/exports ]] && cp /etc/exports "/etc/exports.bak.$(date +%Y%m%d%H%M%S)"

    cat >> /etc/exports <<EOF
${nfs_dir}    ${nfs_client}(${perm},sync,no_subtree_check,no_root_squash)
EOF

    ok "配置已写入 /etc/exports"

    # 生效
    exportfs -ra

    # 启动
    echo ""
    info "启动 NFS 服务..."
    systemctl enable nfs-server nfs-kernel-server 2>/dev/null
    systemctl restart nfs-server nfs-kernel-server 2>/dev/null || true

    # 防火墙
    open_firewall_port 2049
    open_firewall_port 111

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● NFS 共享已配置！${NC}"
    echo -e "  ${BLUE}共享路径：${NC}${nfs_dir}"
    echo -e "  ${BLUE}客户端  ：${NC}${nfs_client}"
    echo -e "  ${BLUE}权限    ：${NC}${perm}"
    echo ""
    echo -e "  ${YELLOW}客户端挂载命令：${NC}"
    echo -e "  ${CYAN}mount -t nfs ${server_ip}:${nfs_dir} /mnt/nfs${NC}"

    sep
}

#-------------------- 功能 6：管理 NFS 共享 --------------------
manage_nfs_shares() {
    sep
    echo -e "${BOLD}          管理 NFS 共享目录${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}当前 NFS 共享：${NC}"
    echo ""
    cat /etc/exports 2>/dev/null | grep -v "^#" | grep -v "^$" || warn "无共享"
    echo ""

    echo -e "  ${CYAN} 1)${NC} 添加共享    ${CYAN} 2)${NC} 删除共享"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  共享路径: "
            read -r nfs_path
            mkdir -p "$nfs_path"
            echo -n "  客户端（* 全部）: "
            read -r nfs_client
            nfs_client="${nfs_client:-*}"
            echo -n "  权限（rw/ro，默认 rw）: "
            read -r perm
            perm="${perm:-rw}"

            echo "${nfs_path}    ${nfs_client}(${perm},sync,no_subtree_check,no_root_squash)" >> /etc/exports
            exportfs -ra
            ok "共享已添加"
            ;;
        2)
            echo -n "  要删除的共享路径: "
            read -r del_path
            sed -i "\|^${del_path}|d" /etc/exports
            exportfs -ra
            ok "共享已删除"
            ;;
    esac
    sep
}

#-------------------- 功能 7：NFS 服务控制 --------------------
control_nfs() {
    sep
    echo -e "${BOLD}          NFS 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start nfs-server nfs-kernel-server 2>/dev/null; ok "已启动" ;;
        2) systemctl stop nfs-server nfs-kernel-server 2>/dev/null; ok "已停止" ;;
        3) systemctl restart nfs-server nfs-kernel-server 2>/dev/null; ok "已重启" ;;
        4) systemctl status nfs-server nfs-kernel-server --no-pager -l 2>/dev/null ;;
    esac
    sep
}

#=============================================================================
#                           FTP 共享（vsftpd）
#=============================================================================

#-------------------- 功能 8：安装配置 vsftpd --------------------
install_vsftpd() {
    sep
    echo -e "${BOLD}          安装并配置 vsftpd（FTP 服务器）${NC}"
    sep
    echo ""

    info "安装 vsftpd..."
    pkg_install vsftpd
    ok "vsftpd 安装完成"
    echo ""

    echo -n "  FTP 共享目录（默认 ${SHARE_DIR}）: "
    read -r ftp_dir
    ftp_dir="${ftp_dir:-$SHARE_DIR}"
    create_share_dir "$ftp_dir"

    echo -e "  ${BOLD}配置选项：${NC}"
    echo -n "  允许匿名访问？(y/N): "
    read -r anon_ok
    echo -n "  允许本地用户登录？(Y/n): "
    read -r local_ok
    local_ok=$( [[ "$local_ok" =~ ^[Nn]$ ]] && echo "NO" || echo "YES" )
    echo -n "  允许写入？(Y/n): "
    read -r write_ok
    write_ok=$( [[ "$write_ok" =~ ^[Nn]$ ]] && echo "NO" || echo "YES" )

    echo ""
    info "写入 vsftpd 配置..."

    local conf_file="/etc/vsftpd.conf"
    [[ -f /etc/vsftpd/vsftpd.conf ]] && conf_file="/etc/vsftpd/vsftpd.conf"

    # 备份
    [[ -f "$conf_file" ]] && cp "$conf_file" "${conf_file}.bak.$(date +%Y%m%d%H%M%S)"

    cat > "$conf_file" <<EOF
# vsftpd 配置 - $(date '+%Y-%m-%d %H:%M:%S')

# 基本设置
listen=YES
listen_ipv6=NO
connect_from_port_20=YES

# 匿名访问
anonymous_enable=$([[ "$anon_ok" =~ ^[Yy]$ ]] && echo "YES" || echo "NO")
anon_root=${ftp_dir}
anon_max_rate=0

# 本地用户
local_enable=${local_ok}
write_enable=${write_ok}
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES

# 目录
local_root=${ftp_dir}

# 日志
xferlog_enable=YES
xferlog_std_format=YES

# 安全
tcp_wrappers=YES
max_clients=50
max_per_ip=5
EOF

    ok "配置已写入 ${conf_file}"

    # 启动
    echo ""
    info "启动 vsftpd..."
    systemctl enable vsftpd 2>/dev/null
    systemctl restart vsftpd 2>/dev/null

    # 防火墙
    open_firewall_port 21
    # 被动模式端口范围
    for p in $(seq 30000 30010); do open_firewall_port "$p"; done

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● vsftpd 已配置！${NC}"
    echo -e "  ${BLUE}共享目录：${NC}${ftp_dir}"
    echo -e "  ${BLUE}匿名访问：${NC}$([[ "$anon_ok" =~ ^[Yy]$ ]] && echo "是" || echo "否")"
    echo -e "  ${BLUE}本地用户：${NC}${local_ok}"
    echo -e "  ${BLUE}写入    ：${NC}${write_ok}"
    echo -e "  ${BLUE}访问地址：${NC}ftp://${server_ip}"

    sep
}

#-------------------- 功能 9：管理 FTP 用户 --------------------
manage_ftp_users() {
    sep
    echo -e "${BOLD}          管理 FTP 用户${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 添加 FTP 用户"
    echo -e "  ${CYAN} 2)${NC} 修改 FTP 用户密码"
    echo -e "  ${CYAN} 3)${NC} 删除 FTP 用户"
    echo -e "  ${CYAN} 4)${NC} 查看所有 FTP 用户"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  用户名: "
            read -r ftp_user
            echo -n "  共享目录（默认 ${SHARE_DIR}）: "
            read -r ftp_home
            ftp_home="${ftp_home:-$SHARE_DIR}"
            mkdir -p "$ftp_home"

            useradd -d "$ftp_home" -s /sbin/nologin "$ftp_user"
            passwd "$ftp_user"
            chown -R "$ftp_user":"$ftp_user" "$ftp_home"
            ok "FTP 用户 ${ftp_user} 已创建"
            ;;
        2)
            echo -n "  用户名: "
            read -r ftp_user
            passwd "$ftp_user"
            ok "密码已修改"
            ;;
        3)
            echo -n "  用户名: "
            read -r ftp_user
            userdel "$ftp_user"
            ok "用户 ${ftp_user} 已删除"
            ;;
        4)
            echo ""
            grep "/sbin/nologin" /etc/passwd | while read -r line; do
                local u=$(echo "$line" | cut -d: -f1)
                local h=$(echo "$line" | cut -d: -f6)
                echo -e "  ${CYAN}${u}${NC} → ${h}"
            done
            ;;
    esac
    sep
}

#-------------------- 功能 10：FTP 服务控制 --------------------
control_ftp() {
    sep
    echo -e "${BOLD}          FTP 服务控制${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start vsftpd; ok "已启动" ;;
        2) systemctl stop vsftpd; ok "已停止" ;;
        3) systemctl restart vsftpd; ok "已重启" ;;
        4) systemctl status vsftpd --no-pager -l ;;
    esac
    sep
}

#=============================================================================
#                           WebDAV 共享（Nginx）
#=============================================================================

#-------------------- 功能 11：安装配置 WebDAV --------------------
install_webdav() {
    sep
    echo -e "${BOLD}          安装并配置 WebDAV（Nginx）${NC}"
    sep
    echo ""

    info "安装 Nginx 和 WebDAV 模块..."
    case "$OS_ID" in
        ubuntu|debian)
            pkg_install nginx nginx-extras
            ;;
        *)
            pkg_install nginx
            # 确保 mod_http_dav_module 已编译
            nginx -V 2>&1 | grep -q "http_dav_module" || warn "Nginx 未包含 dav 模块"
            ;;
    esac
    ok "Nginx 安装完成"
    echo ""

    echo -n "  WebDAV 共享目录（默认 ${SHARE_DIR}）: "
    read -r webdav_dir
    webdav_dir="${webdav_dir:-$SHARE_DIR}"
    create_share_dir "$webdav_dir"
    chown -R www-data:www-data "$webdav_dir" 2>/dev/null || chown -R nginx:nginx "$webdav_dir" 2>/dev/null

    echo -n "  监听端口（默认 8080）: "
    read -r webdav_port
    webdav_port="${webdav_port:-8080}"

    echo -n "  用户名（默认 admin）: "
    read -r webdav_user
    webdav_user="${webdav_user:-admin}"

    echo -n "  密码: "
    read -r -s webdav_pass
    echo ""

    echo ""
    info "创建 htpasswd 认证文件..."

    # 安装 apache2-utils 或 httpd-tools
    case "$OS_ID" in
        ubuntu|debian) pkg_install apache2-utils ;;
        *) pkg_install httpd-tools ;;
    esac

    htpasswd -bc /etc/nginx/.webdav_htpasswd "$webdav_user" "$webdav_pass" 2>/dev/null
    ok "认证文件已创建"

    info "写入 Nginx WebDAV 配置..."

    cat > /etc/nginx/conf.d/webdav.conf <<EOF
server {
    listen ${webdav_port};
    server_name _;

    # WebDAV 共享
    location / {
        root ${webdav_dir};
        client_body_temp_path /tmp/webdav_temp;

        # DAV 配置
        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS LOCK UNLOCK;
        dav_access user:rw group:rw all:r;

        # 自动创建目录
        create_full_put_path on;

        # 认证
        auth_basic "WebDAV Restricted";
        auth_basic_user_file /etc/nginx/.webdav_htpasswd;

        # 允许大文件
        client_max_body_size 0;
        allow all;
    }
}
EOF

    # 创建临时目录
    mkdir -p /tmp/webdav_temp
    chown www-data:www-data /tmp/webdav_temp 2>/dev/null || chown nginx:nginx /tmp/webdav_temp 2>/dev/null

    ok "配置已写入 /etc/nginx/conf.d/webdav.conf"

    # 测试并启动
    echo ""
    info "测试 Nginx 配置..."
    if nginx -t 2>/dev/null; then
        ok "配置测试通过"
        systemctl enable nginx 2>/dev/null
        systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
    else
        error "Nginx 配置测试失败，请检查"
        return
    fi

    # 防火墙
    open_firewall_port "$webdav_port"

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● WebDAV 已配置！${NC}"
    echo -e "  ${BLUE}共享目录：${NC}${webdav_dir}"
    echo -e "  ${BLUE}端口    ：${NC}${webdav_port}"
    echo -e "  ${BLUE}用户名  ：${NC}${webdav_user}"
    echo -e "  ${BLUE}访问地址：${NC}http://${server_ip}:${webdav_port}/"
    echo ""
    echo -e "  ${YELLOW}客户端访问：${NC}"
    echo -e "  ${CYAN}Windows: 映射网络驱动器 → http://${server_ip}:${webdav_port}/${NC}"
    echo -e "  ${CYAN}Linux:   mount -t davfs http://${server_ip}:${webdav_port}/ /mnt/webdav${NC}"

    sep
}

#-------------------- 功能 12：管理 WebDAV 用户 --------------------
manage_webdav_users() {
    sep
    echo -e "${BOLD}          管理 WebDAV 用户${NC}"
    sep
    echo ""

    local htpasswd_file="/etc/nginx/.webdav_htpasswd"

    if [[ ! -f "$htpasswd_file" ]]; then
        warn "未找到 WebDAV 认证文件，请先安装 WebDAV"
        return
    fi

    echo -e "  ${BOLD}当前用户：${NC}"
    cat "$htpasswd_file" | while IFS=: read -r u _; do
        echo -e "    ${CYAN}${u}${NC}"
    done
    echo ""

    echo -e "  ${CYAN} 1)${NC} 添加用户    ${CYAN} 2)${NC} 修改密码    ${CYAN} 3)${NC} 删除用户"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  用户名: "
            read -r username
            echo -n "  密码: "
            read -r -s password
            echo ""
            htpasswd -b "$htpasswd_file" "$username" "$password"
            ok "用户 ${username} 已添加"
            systemctl reload nginx 2>/dev/null
            ;;
        2)
            echo -n "  用户名: "
            read -r username
            echo -n "  新密码: "
            read -r -s password
            echo ""
            htpasswd -b "$htpasswd_file" "$username" "$password"
            ok "密码已修改"
            systemctl reload nginx 2>/dev/null
            ;;
        3)
            echo -n "  用户名: "
            read -r username
            htpasswd -D "$htpasswd_file" "$username"
            ok "用户 ${username} 已删除"
            systemctl reload nginx 2>/dev/null
            ;;
    esac
    sep
}

#-------------------- 功能 13：WebDAV 服务控制 --------------------
control_webdav() {
    sep
    echo -e "${BOLD}          WebDAV 服务控制（Nginx）${NC}"
    sep
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动    ${CYAN} 2)${NC} 停止    ${CYAN} 3)${NC} 重启    ${CYAN} 4)${NC} 状态"
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1) systemctl start nginx; ok "已启动" ;;
        2) systemctl stop nginx; ok "已停止" ;;
        3) systemctl restart nginx; ok "已重启" ;;
        4) systemctl status nginx --no-pager -l ;;
    esac
    sep
}

#=============================================================================
#                           SFTP 共享（基于 SSH）
#=============================================================================

#-------------------- 功能 14：配置 SFTP --------------------
configure_sftp() {
    sep
    echo -e "${BOLD}          配置 SFTP（基于 SSH）${NC}"
    sep
    echo ""

    if ! command -v sshd &>/dev/null; then
        info "安装 OpenSSH..."
        case "$OS_ID" in
            ubuntu|debian) pkg_install openssh-server ;;
            *) pkg_install openssh-server ;;
        esac
    fi
    ok "OpenSSH 已安装"
    echo ""

    echo -e "  ${YELLOW}SFTP 基于 SSH，默认使用 22 端口，传输加密${NC}"
    echo ""

    echo -n "  SFTP 共享目录（默认 ${SHARE_DIR}）: "
    read -r sftp_dir
    sftp_dir="${sftp_dir:-$SHARE_DIR}"

    # 创建目录结构（chroot 要求）
    mkdir -p "${sftp_dir}"
    chown root:root "$sftp_dir"
    chmod 755 "$sftp_dir"

    # 创建可写子目录
    mkdir -p "${sftp_dir}/upload"
    chmod 777 "${sftp_dir}/upload"

    ok "SFTP 目录已创建: ${sftp_dir}"
    echo ""

    # 配置 sshd_config
    local sshd_config="/etc/ssh/sshd_config"
    [[ -f /etc/ssh/sshd_config.d/sshd_config ]] && sshd_config="/etc/ssh/sshd_config"

    info "配置 SSH SFTP 子系统..."

    # 检查是否已有配置
    if grep -q "ForceCommand internal-sftp" "$sshd_config" 2>/dev/null; then
        warn "sshd_config 中已有 SFTP 配置，跳过"
    else
        # 备份
        cp "$sshd_config" "${sshd_config}.bak.$(date +%Y%m%d%H%M%S)"

        cat >> "$sshd_config" <<EOF

# ===== SFTP 配置 =====
# 匹配 SFTP 专用用户组
Match Group sftpusers
    ChrootDirectory ${sftp_dir}
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
EOF
        ok "SFTP 配置已写入 ${sshd_config}"
    fi

    # 创建 sftpusers 组
    groupadd sftpusers 2>/dev/null || true

    # 重启 SSH
    echo ""
    info "重启 SSH 服务..."
    systemctl restart sshd ssh 2>/dev/null || true

    # 防火墙
    open_firewall_port 22

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}● SFTP 已配置！${NC}"
    echo -e "  ${BLUE}共享目录：${NC}${sftp_dir}"
    echo -e "  ${BLUE}上传目录：${NC}${sftp_dir}/upload（可写）"
    echo -e "  ${BLUE}端口    ：${NC}22"
    echo -e "  ${BLUE}用户组  ：${NC}sftpusers"
    echo ""
    echo -e "  ${YELLOW}添加 SFTP 用户请使用菜单 15${NC}"
    echo -e "  ${YELLOW}客户端访问：${NC}"
    echo -e "  ${CYAN}sftp username@${server_ip}${NC}"
    echo -e "  ${CYAN}FileZilla: sftp://${server_ip}:22${NC}"

    sep
}

#-------------------- 功能 15：管理 SFTP 用户 --------------------
manage_sftp_users() {
    sep
    echo -e "${BOLD}          管理 SFTP 用户（chroot 隔离）${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}当前 SFTP 用户：${NC}"
    echo ""
    getent group sftpusers 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read -r u; do
        [[ -n "$u" ]] && echo -e "    ${CYAN}${u}${NC}"
    done || warn "无 SFTP 用户"
    echo ""

    echo -e "  ${CYAN} 1)${NC} 添加 SFTP 用户"
    echo -e "  ${CYAN} 2)${NC} 修改密码"
    echo -e "  ${CYAN} 3)${NC} 删除 SFTP 用户"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  用户名: "
            read -r sftp_user
            echo -n "  密码: "
            read -r -s sftp_pass
            echo ""

            useradd -m -s /sbin/nologin -G sftpusers "$sftp_user"
            echo "${sftp_user}:${sftp_pass}" | chpasswd

            # 创建用户专属上传目录
            local sftp_base=$(grep "ChrootDirectory" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
            if [[ -n "$sftp_base" ]]; then
                mkdir -p "${sftp_base}/${sftp_user}"
                chown "${sftp_user}:sftpusers" "${sftp_base}/${sftp_user}"
                chmod 755 "${sftp_base}/${sftp_user}"
            fi

            ok "SFTP 用户 ${sftp_user} 已创建"
            ;;
        2)
            echo -n "  用户名: "
            read -r sftp_user
            passwd "$sftp_user"
            ok "密码已修改"
            ;;
        3)
            echo -n "  用户名: "
            read -r sftp_user
            userdel -r "$sftp_user" 2>/dev/null || userdel "$sftp_user"
            ok "用户 ${sftp_user} 已删除"
            ;;
    esac
    sep
}

#=============================================================================
#                           综合管理
#=============================================================================

#-------------------- 功能 16：一键部署全部 --------------------
deploy_all() {
    sep
    echo -e "${BOLD}          一键部署全部共享协议${NC}"
    sep
    echo ""

    warn "将安装并配置 SMB + NFS + FTP + WebDAV + SFTP"
    echo -e "  ${YELLOW}共享目录统一为：${SHARE_DIR}${NC}"
    echo ""

    echo -n "  确认全部部署？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    mkdir -p "$SHARE_DIR"

    # SMB
    echo ""
    info "=== [1/5] 安装 Samba ==="
    pkg_install samba samba-common
    cat >> /etc/samba/smb.conf <<EOF

[share]
    path = ${SHARE_DIR}
    browseable = yes
    writable = yes
    guest ok = yes
    force user = root
    create mask = 0664
    directory mask = 0775
EOF
    systemctl enable smbd smb 2>/dev/null
    systemctl restart smbd smb nmbd nmb 2>/dev/null || true
    ok "Samba 完成"

    # NFS
    echo ""
    info "=== [2/5] 安装 NFS ==="
    case "$OS_ID" in
        ubuntu|debian) pkg_install nfs-kernel-server ;;
        *) pkg_install nfs-utils ;;
    esac
    echo "${SHARE_DIR}    *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra
    systemctl enable nfs-server nfs-kernel-server 2>/dev/null
    systemctl restart nfs-server nfs-kernel-server 2>/dev/null || true
    ok "NFS 完成"

    # FTP
    echo ""
    info "=== [3/5] 安装 vsftpd ==="
    pkg_install vsftpd
    cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=YES
anon_root=${SHARE_DIR}
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=${SHARE_DIR}
connect_from_port_20=YES
xferlog_enable=YES
EOF
    systemctl enable vsftpd 2>/dev/null
    systemctl restart vsftpd 2>/dev/null
    ok "vsftpd 完成"

    # WebDAV
    echo ""
    info "=== [4/5] 安装 WebDAV ==="
    case "$OS_ID" in
        ubuntu|debian) pkg_install nginx nginx-extras apache2-utils ;;
        *) pkg_install nginx httpd-tools ;;
    esac
    htpasswd -bc /etc/nginx/.webdav_htpasswd admin admin123 2>/dev/null
    cat > /etc/nginx/conf.d/webdav.conf <<EOF
server {
    listen 8080;
    location / {
        root ${SHARE_DIR};
        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS LOCK UNLOCK;
        dav_access user:rw group:rw all:r;
        create_full_put_path on;
        auth_basic "WebDAV";
        auth_basic_user_file /etc/nginx/.webdav_htpasswd;
        client_max_body_size 0;
    }
}
EOF
    systemctl enable nginx 2>/dev/null
    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null
    ok "WebDAV 完成"

    # SFTP
    echo ""
    info "=== [5/5] 配置 SFTP ==="
    groupadd sftpusers 2>/dev/null || true
    if ! grep -q "ForceCommand internal-sftp" /etc/ssh/sshd_config 2>/dev/null; then
        cat >> /etc/ssh/sshd_config <<EOF

Match Group sftpusers
    ChrootDirectory ${SHARE_DIR}
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF
    fi
    mkdir -p "${SHARE_DIR}/upload"
    chmod 777 "${SHARE_DIR}/upload"
    systemctl restart sshd ssh 2>/dev/null || true
    ok "SFTP 完成"

    # 防火墙
    echo ""
    info "配置防火墙..."
    open_firewall_port 445
    open_firewall_port 139
    open_firewall_port 2049
    open_firewall_port 111
    open_firewall_port 21
    open_firewall_port 22
    open_firewall_port 8080

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo ""
    echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}${BOLD}          ● 全部协议部署完成！${NC}"
    echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}共享目录：${NC}${SHARE_DIR}"
    echo ""
    echo -e "  ${CYAN}SMB/CIFS: ${NC}\\\\${server_ip}\\share"
    echo -e "  ${CYAN}NFS:      ${NC}${server_ip}:${SHARE_DIR}"
    echo -e "  ${CYAN}FTP:      ${NC}ftp://${server_ip}"
    echo -e "  ${CYAN}WebDAV:   ${NC}http://${server_ip}:8080/  ${YELLOW}(admin/admin123)${NC}"
    echo -e "  ${CYAN}SFTP:     ${NC}sftp://${server_ip}:22"

    sep
}

#-------------------- 功能 17：查看所有共享状态 --------------------
show_all_status() {
    sep
    echo -e "${BOLD}          所有共享协议状态${NC}"
    sep
    echo ""

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo -e "  ${BOLD}--- SMB/CIFS ---${NC}"
    if systemctl is-active --quiet smbd 2>/dev/null || systemctl is-active --quiet smb 2>/dev/null; then
        echo -e "  ${GREEN}● 运行中${NC}  端口: 445/139"
        echo -e "  ${CYAN}访问: \\\\${server_ip}\\share${NC}"
    else
        echo -e "  ${RED}○ 未运行${NC}"
    fi
    echo ""

    echo -e "  ${BOLD}--- NFS ---${NC}"
    if systemctl is-active --quiet nfs-server 2>/dev/null || systemctl is-active --quiet nfs-kernel-server 2>/dev/null; then
        echo -e "  ${GREEN}● 运行中${NC}  端口: 2049"
        echo -e "  ${CYAN}访问: mount -t nfs ${server_ip}:${SHARE_DIR}${NC}"
        echo ""
        echo -e "  ${BOLD}当前导出：${NC}"
        exportfs -v 2>/dev/null | while read -r line; do
            echo -e "    ${line}"
        done
    else
        echo -e "  ${RED}○ 未运行${NC}"
    fi
    echo ""

    echo -e "  ${BOLD}--- FTP ---${NC}"
    if systemctl is-active --quiet vsftpd 2>/dev/null; then
        echo -e "  ${GREEN}● 运行中${NC}  端口: 21"
        echo -e "  ${CYAN}访问: ftp://${server_ip}${NC}"
    else
        echo -e "  ${RED}○ 未运行${NC}"
    fi
    echo ""

    echo -e "  ${BOLD}--- WebDAV ---${NC}"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        local port=$(grep "listen" /etc/nginx/conf.d/webdav.conf 2>/dev/null | head -1 | grep -o '[0-9]*' || echo "8080")
        echo -e "  ${GREEN}● 运行中${NC}  端口: ${port}"
        echo -e "  ${CYAN}访问: http://${server_ip}:${port}/${NC}"
    else
        echo -e "  ${RED}○ 未运行${NC}"
    fi
    echo ""

    echo -e "  ${BOLD}--- SFTP ---${NC}"
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "  ${GREEN}● 运行中${NC}  端口: 22"
        echo -e "  ${CYAN}访问: sftp://${server_ip}:22${NC}"
    else
        echo -e "  ${RED}○ 未运行${NC}"
    fi

    sep
}

#-------------------- 功能 18：防火墙配置 --------------------
setup_firewall() {
    sep
    echo -e "${BOLD}          防火墙一键放行共享端口${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}将放行以下端口：${NC}"
    echo -e "  ${CYAN}SMB/CIFS${NC}:  445/tcp, 139/tcp"
    echo -e "  ${CYAN}NFS${NC}:      2049/tcp, 111/tcp"
    echo -e "  ${CYAN}FTP${NC}:      21/tcp, 30000-30010/tcp（被动模式）"
    echo -e "  ${CYAN}WebDAV${NC}:   8080/tcp（或自定义端口）"
    echo -e "  ${CYAN}SFTP${NC}:     22/tcp"
    echo ""

    echo -n "  确认放行？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    info "放行端口..."

    # SMB
    open_firewall_port 445
    open_firewall_port 139
    # NFS
    open_firewall_port 2049
    open_firewall_port 111
    # FTP
    open_firewall_port 21
    for p in $(seq 30000 30010); do open_firewall_port "$p"; done
    # WebDAV
    open_firewall_port 8080
    # SFTP
    open_firewall_port 22

    ok "所有共享端口已放行"

    sep
}

#-------------------- 功能 19：查看连接日志 --------------------
show_logs() {
    sep
    echo -e "${BOLD}          共享连接日志${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}选择日志：${NC}"
    echo -e "  ${CYAN} 1)${NC} Samba 日志"
    echo -e "  ${CYAN} 2)${NC} NFS 日志"
    echo -e "  ${CYAN} 3)${NC} FTP 日志"
    echo -e "  ${CYAN} 4)${NC} WebDAV/Nginx 日志"
    echo -e "  ${CYAN} 5)${NC} SFTP/SSH 日志"
    echo ""
    echo -n "请选择: "
    read -r choice

    echo ""
    case "$choice" in
        1)
            echo -e "  ${BOLD}--- Samba 日志（最近 30 条）---${NC}"
            journalctl -u smbd -u smb -n 30 --no-pager 2>/dev/null || tail -30 /var/log/samba/log.smbd 2>/dev/null || warn "无日志"
            ;;
        2)
            echo -e "  ${BOLD}--- NFS 日志（最近 30 条）---${NC}"
            journalctl -u nfs-server -u nfs-kernel-server -n 30 --no-pager 2>/dev/null || warn "无日志"
            ;;
        3)
            echo -e "  ${BOLD}--- FTP 日志（最近 30 条）---${NC}"
            journalctl -u vsftpd -n 30 --no-pager 2>/dev/null || tail -30 /var/log/vsftpd.log 2>/dev/null || warn "无日志"
            ;;
        4)
            echo -e "  ${BOLD}--- Nginx WebDAV 日志（最近 30 条）---${NC}"
            tail -30 /var/log/nginx/access.log 2>/dev/null || journalctl -u nginx -n 30 --no-pager 2>/dev/null || warn "无日志"
            ;;
        5)
            echo -e "  ${BOLD}--- SSH/SFTP 日志（最近 30 条）---${NC}"
            journalctl -u sshd -u ssh -n 30 --no-pager 2>/dev/null || tail -30 /var/log/auth.log 2>/dev/null || warn "无日志"
            ;;
    esac

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
            1) install_samba ;;
            2) manage_smb_users ;;
            3) manage_smb_shares ;;
            4) control_samba ;;
            5) install_nfs ;;
            6) manage_nfs_shares ;;
            7) control_nfs ;;
            8) install_vsftpd ;;
            9) manage_ftp_users ;;
            10) control_ftp ;;
            11) install_webdav ;;
            12) manage_webdav_users ;;
            13) control_webdav ;;
            14) configure_sftp ;;
            15) manage_sftp_users ;;
            16) deploy_all ;;
            17) show_all_status ;;
            18) setup_firewall ;;
            19) show_logs ;;
            0|q|Q)
                echo ""
                info "退出文件共享管理脚本"
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