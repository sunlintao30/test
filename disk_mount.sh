#!/bin/bash
#=============================================================================
# 磁盘自动挂载管理脚本
# 功能：SMB / WebDAV 网络磁盘挂载，systemd automount（不阻塞开机），
#       断线自动重连重试，交互式配置管理
# 支持：Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora
# 用法：chmod +x disk_mount.sh && sudo ./disk_mount.sh
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
MOUNT_CONFIG_DIR="/etc/disk_mount_configs"
CREDENTIALS_DIR="/etc/disk_mount_credentials"
RECONNECT_SCRIPT="/usr/local/bin/disk_mount_reconnect.sh"
RECONNECT_TIMER_DIR="/etc/systemd/system"

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}          磁盘自动挂载管理（SMB / WebDAV）${NC}"
    sep
    echo ""

    # 显示当前挂载状态
    echo -e "  ${BOLD}当前挂载状态：${NC}"
    echo ""
    local has_mount=false

    # 读取配置目录中的所有挂载配置
    if [[ -d "$MOUNT_CONFIG_DIR" ]]; then
        for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
            [[ -f "$cfg_file" ]] || continue

            source "$cfg_file"

            local mount_point="${MOUNT_POINT}"
            local mount_type="${MOUNT_TYPE}"
            local server_url="${SERVER_URL}"
            local name=$(basename "$cfg_file" .conf)

            echo -n "  ${CYAN}[${name}]${NC} "
            echo -n "${BLUE}${mount_type}${NC} → "
            echo -n "${CYAN}${mount_point}${NC}  "

            if mountpoint -q "$mount_point" 2>/dev/null; then
                echo -e "${GREEN}● 已挂载${NC}"
            else
                echo -e "${RED}○ 未挂载${NC}"
            fi

            has_mount=true
        done
    fi

    if [[ "$has_mount" == false ]]; then
        echo -e "    ${YELLOW}暂无挂载配置${NC}"
    fi

    echo ""

    # 检查重连服务状态
    echo -n "  ${BLUE}断线重连服务：${NC}"
    if systemctl is-active --quiet disk-mount-reconnect.timer 2>/dev/null; then
        echo -e "${GREEN}运行中${NC}"
    elif [[ -f "${RECONNECT_TIMER_DIR}/disk-mount-reconnect.timer" ]]; then
        echo -e "${YELLOW}已配置但未运行${NC}"
    else
        echo -e "${YELLOW}未配置${NC}"
    fi

    echo ""
    sep
    echo ""

    echo -e "  ${CYAN}【挂载管理】${NC}"
    echo -e "  ${CYAN} 1)${NC} 添加 SMB/CIFS 挂载"
    echo -e "  ${CYAN} 2)${NC} 添加 WebDAV 挂载"
    echo -e "  ${CYAN} 3)${NC} 手动挂载全部"
    echo -e "  ${CYAN} 4)${NC} 手动卸载全部"
    echo ""
    echo -e "  ${CYAN}【挂载操作】${NC}"
    echo -e "  ${CYAN} 5)${NC} 挂载/卸载单个挂载点"
    echo -e "  ${CYAN} 6)${NC} 测试挂载连接"
    echo ""
    echo -e "  ${CYAN}【断线重连】${NC}"
    echo -e "  ${CYAN} 7)${NC} 配置断线自动重连（systemd timer）"
    echo -e "  ${CYAN} 8)${NC} 查看重连日志"
    echo -e "  ${CYAN} 9)${NC} 启用/禁用重连服务"
    echo ""
    echo -e "  ${CYAN}【配置管理】${NC}"
    echo -e "  ${CYAN}10)${NC} 查看所有挂载配置"
    echo -e "  ${CYAN}11)${NC} 删除挂载配置"
    echo -e "  ${CYAN}12)${NC} 修改挂载配置"
    echo -e ""
    echo -e "  ${CYAN} 0)${NC} 退出"
    echo ""
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：添加 SMB 挂载 --------------------
add_smb_mount() {
    sep
    echo -e "${BOLD}          添加 SMB/CIFS 网络挂载${NC}"
    sep
    echo ""

    echo -e "  ${YELLOW}挂载方式说明：${NC}"
    echo -e "  ${GREEN}● systemd automount${NC} - 访问挂载点时才连接，${BOLD}不阻塞开机${BOLD}"
    echo -e "  ${GREEN}● systemd mount${NC}    - 开机自动挂载（等待网络），失败不卡住"
    echo ""

    # 挂载名称（用作配置文件名）
    echo -n "  挂载名称（英文，如 nas、share，用于标识）: "
    read -r mount_name
    mount_name=$(echo "$mount_name" | tr -cd 'a-zA-Z0-9_-')
    if [[ -z "$mount_name" ]]; then
        error "名称不能为空"
        return
    fi

    # 服务器地址
    echo -n "  SMB 服务器地址（如 192.168.1.100 或 nas.example.com）: "
    read -r server_addr
    if [[ -z "$server_addr" ]]; then
        error "服务器地址不能为空"
        return
    fi

    # 共享名称
    echo -n "  共享名称（如 share、data、movies）: "
    read -r share_name
    if [[ -z "$share_name" ]]; then
        error "共享名称不能为空"
        return
    fi

    # 端口
    echo -n "  端口号（默认 445）: "
    read -r port
    port="${port:-445}"

    # 挂载点
    local default_mp="/mnt/smb_${mount_name}"
    echo -n "  本地挂载路径（默认 ${default_mp}）: "
    read -r mount_point
    mount_point="${mount_point:-$default_mp}"

    # 用户名
    echo -n "  SMB 用户名（留空为匿名访问）: "
    read -r smb_user

    # 密码
    echo -n "  SMB 密码（留空为空密码）: "
    read -r -s smb_pass
    echo ""

    # 域（可选）
    echo -n "  域/工作组（留空跳过）: "
    read -r smb_domain

    # 挂载方式选择
    echo ""
    echo -e "  ${BOLD}选择挂载方式：${NC}"
    echo -e "  ${CYAN} 1)${NC} systemd automount ${GREEN}（推荐，访问时才连接，开机零影响）${NC}"
    echo -e "  ${CYAN} 2)${NC} systemd mount ${YELLOW}（开机自动挂载，网络就绪后连接）${NC}"
    echo ""
    echo -n "请选择 [1-2]（默认 1）: "
    read -r mount_mode
    mount_mode="${mount_mode:-1}"

    # 额外挂载选项
    echo ""
    echo -e "  ${BOLD}高级选项（一般使用默认即可）：${NC}"
    echo -n "  文件权限模式（默认 0664）: "
    read -r file_mode
    file_mode="${file_mode:-0664}"

    echo -n "  目录权限模式（默认 0775）: "
    read -r dir_mode
    dir_mode="${dir_mode:-0775}"

    echo -n "  UID（留空使用当前用户）: "
    read -r uid_val
    uid_val="${uid_val:-$(id -u)"

    echo -n "  GID（留空使用当前组）: "
    read -r gid_val
    gid_val="${gid_val:-$(id -g)}"

    # 构建服务器 URL
    local server_url="//${server_addr}/${share_name}"

    # 确认
    echo ""
    sep_s
    echo -e "  ${BOLD}配置确认：${NC}"
    echo -e "  ${BLUE}类型    ：${NC}SMB/CIFS"
    echo -e "  ${BLUE}服务器  ：${NC}${server_url}"
    echo -e "  ${BLUE}端口    ：${NC}${port}"
    echo -e "  ${BLUE}挂载点  ：${NC}${mount_point}"
    echo -e "  ${BLUE}用户名  ：${NC}${smb_user:-匿名}"
    echo -e "  ${BLUE}挂载方式：${NC}$([ "$mount_mode" == "1" ] && echo "automount" || echo "mount")"
    sep_s
    echo ""
    echo -n "  确认创建？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "开始配置..."

    # 创建目录
    mkdir -p "$MOUNT_CONFIG_DIR" "$CREDENTIALS_DIR"
    mkdir -p "$mount_point"

    # 保存凭据文件
    if [[ -n "$smb_user" ]]; then
        local cred_file="${CREDENTIALS_DIR}/${mount_name}.cred"
        cat > "$cred_file" <<EOF
username=${smb_user}
password=${smb_pass}
EOF
        [[ -n "$smb_domain" ]] && echo "domain=${smb_domain}" >> "$cred_file"
        chmod 600 "$cred_file"
        ok "凭据文件已保存: ${cred_file}"
    fi

    # 保存配置
    local cfg_file="${MOUNT_CONFIG_DIR}/${mount_name}.conf"
    cat > "$cfg_file" <<EOF
# SMB 挂载配置 - ${mount_name}
# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')
MOUNT_TYPE="smb"
SERVER_URL="${server_url}"
SERVER_ADDR="${server_addr}"
SHARE_NAME="${share_name}"
PORT="${port}"
MOUNT_POINT="${mount_point}"
MOUNT_MODE="${mount_mode}"
SMB_USER="${smb_user}"
SMB_DOMAIN="${smb_domain}"
CRED_FILE="${CREDENTIALS_DIR}/${mount_name}.cred"
FILE_MODE="${file_mode}"
DIR_MODE="${dir_mode}"
UID="${uid_val}"
GID="${gid_val}"
EOF
    chmod 600 "$cfg_file"

    # 创建 systemd 单元文件
    create_smb_systemd "$mount_name" "$server_url" "$mount_point" "$port" "$mount_mode" "$uid_val" "$gid_val" "$file_mode" "$dir_mode" "$smb_user"

    ok "SMB 挂载配置创建完成"
    echo ""

    echo -e "  ${GREEN}${BOLD}● SMB 挂载已配置！${NC}"
    echo -e "  ${BLUE}挂载点：${NC}${mount_point}"
    echo -e "  ${YELLOW}提示：automount 模式下，首次访问 ${mount_point} 时才会触发连接${NC}"

    sep
}

#-------------------- 创建 SMB systemd 单元 --------------------
create_smb_systemd() {
    local name=$1
    local server_url=$2
    local mount_point=$3
    local port=$4
    local mode=$5
    local uid=$6
    local gid=$7
    local file_mode=$8
    local dir_mode=$9
    local smb_user=${10}

    local escaped_mp=$(systemd-escape --path "$mount_point")
    local mount_unit="${RECONNECT_TIMER_DIR}/${escaped_mp}.mount"
    local automount_unit="${RECONNECT_TIMER_DIR}/${escaped_mp}.automount"

    # 构建 options
    local options="uid=${uid},gid=${gid},file_mode=${file_mode},dir_mode=${dir_mode},iocharset=utf8"
    options="${options},vers=3.0"

    if [[ -n "$smb_user" && -f "${CREDENTIALS_DIR}/${name}.cred" ]]; then
        options="${options},credentials=${CREDENTIALS_DIR}/${name}.cred"
    fi

    # mount 单元
    cat > "$mount_unit" <<EOF
[Unit]
Description=Mount SMB/CIFS: ${name} -> ${mount_point}
After=network-online.target
Wants=network-online.target

[Mount]
What=${server_url}
Where=${mount_point}
Type=cifs
Options=${options},_netdev,nofail

[Install]
WantedBy=multi-user.target
EOF

    # automount 单元
    cat > "$automount_unit" <<EOF
[Unit]
Description=Automount SMB/CIFS: ${name} -> ${mount_point}

[Automount]
Where=${mount_point}
TimeoutIdleSec=300
EOF

    # 启用
    systemctl daemon-reload

    if [[ "$mode" == "1" ]]; then
        systemctl enable "${escaped_mp}.automount" 2>/dev/null
        systemctl restart "${escaped_mp}.automount" 2>/dev/null || true
    else
        systemctl enable "${escaped_mp}.mount" 2>/dev/null
        systemctl restart "${escaped_mp}.mount" 2>/dev/null || true
    fi
}

#-------------------- 功能 2：添加 WebDAV 挂载 --------------------
add_webdav_mount() {
    sep
    echo -e "${BOLD}          添加 WebDAV 网络挂载${NC}"
    sep
    echo ""

    # 检查 davfs2
    if ! command -v mount.davfs &>/dev/null; then
        info "安装 davfs2..."
        if command -v apt &>/dev/null; then
            echo "Y" | apt-get install -y davfs2 2>/dev/null || {
                warn "交互安装失败，尝试非交互安装..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y davfs2 2>/dev/null
            }
        elif command -v dnf &>/dev/null; then
            dnf install -y davfs2 fuse davfs2 2>/dev/null
        elif command -v yum &>/dev/null; then
            yum install -y davfs2 fuse davfs2 2>/dev/null
        fi

        if ! command -v mount.davfs &>/dev/null; then
            error "davfs2 安装失败，WebDAV 挂载需要 davfs2"
            echo -e "  ${CYAN}Ubuntu/Debian: apt install davfs2${NC}"
            echo -e "  ${CYAN}CentOS/RHEL:   yum install davfs2 fuse${NC}"
            echo -e "  ${CYAN}Arch Linux:     pacman -S davfs2${NC}"
            return
        fi
    fi
    ok "davfs2 已安装"
    echo ""

    echo -e "  ${YELLOW}挂载方式说明：${NC}"
    echo -e "  ${GREEN}● systemd automount${NC} - 访问挂载点时才连接，${BOLD}不阻塞开机${BOLD}"
    echo -e "  ${GREEN}● systemd mount${NC}    - 开机自动挂载（等待网络），失败不卡住"
    echo ""

    # 挂载名称
    echo -n "  挂载名称（英文，如 aliyun、cloud、webdav）: "
    read -r mount_name
    mount_name=$(echo "$mount_name" | tr -cd 'a-zA-Z0-9_-')
    if [[ -z "$mount_name" ]]; then
        error "名称不能为空"
        return
    fi

    # WebDAV URL
    echo -n "  WebDAV 地址（如 https://dav.example.com/remote.php/webdav/）: "
    read -r dav_url
    if [[ -z "$dav_url" ]]; then
        error "WebDAV 地址不能为空"
        return
    fi
    # 确保 URL 以 / 结尾
    [[ "${dav_url}" != */ ]] && dav_url="${dav_url}/"

    # 挂载点
    local default_mp="/mnt/webdav_${mount_name}"
    echo -n "  本地挂载路径（默认 ${default_mp}）: "
    read -r mount_point
    mount_point="${mount_point:-$default_mp}"

    # 用户名
    echo -n "  WebDAV 用户名: "
    read -r dav_user

    # 密码
    echo -n "  WebDAV 密码: "
    read -r -s dav_pass
    echo ""

    # 挂载方式
    echo ""
    echo -e "  ${BOLD}选择挂载方式：${NC}"
    echo -e "  ${CYAN} 1)${NC} systemd automount ${GREEN}（推荐，访问时才连接）${NC}"
    echo -e "  ${CYAN} 2)${NC} systemd mount ${YELLOW}（开机自动挂载）${NC}"
    echo ""
    echo -n "请选择 [1-2]（默认 1）: "
    read -r mount_mode
    mount_mode="${mount_mode:-1}"

    # UID/GID
    echo -n "  UID（留空使用当前用户 ${UID}）: "
    read -r uid_val
    uid_val="${uid_val:-$(id -u)}"

    echo -n "  GID（留空使用当前组）: "
    read -r gid_val
    gid_val="${gid_val:-$(id -g)}"

    # 确认
    echo ""
    sep_s
    echo -e "  ${BOLD}配置确认：${NC}"
    echo -e "  ${BLUE}类型    ：${NC}WebDAV"
    echo -e "  ${BLUE}服务器  ：${NC}${dav_url}"
    echo -e "  ${BLUE}挂载点  ：${NC}${mount_point}"
    echo -e "  ${BLUE}用户名  ：${NC}${dav_user}"
    echo -e "  ${BLUE}挂载方式：${NC}$([ "$mount_mode" == "1" ] && echo "automount" || echo "mount")"
    sep_s
    echo ""
    echo -n "  确认创建？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "开始配置..."

    # 创建目录
    mkdir -p "$MOUNT_CONFIG_DIR" "$CREDENTIALS_DIR"
    mkdir -p "$mount_point"

    # 保存凭据到 davfs2 secrets
    local secrets_file="/etc/davfs2/secrets"
    if [[ -f "$secrets_file" ]]; then
        # 移除旧的同一挂载点的条目
        sed -i "\|${mount_point}|d" "$secrets_file"
    fi
    echo "${mount_point} ${dav_user} \"${dav_pass}\"" >> "$secrets_file"
    chmod 600 "$secrets_file"
    ok "凭据已保存到 ${secrets_file}"

    # 同时保存到我们的凭据目录
    cat > "${CREDENTIALS_DIR}/${mount_name}.cred" <<EOF
WEBDAV_URL=${dav_url}
WEBDAV_USER=${dav_user}
WEBDAV_PASS=${dav_pass}
EOF
    chmod 600 "${CREDENTIALS_DIR}/${mount_name}.cred"

    # 保存配置
    local cfg_file="${MOUNT_CONFIG_DIR}/${mount_name}.conf"
    cat > "$cfg_file" <<EOF
# WebDAV 挂载配置 - ${mount_name}
# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')
MOUNT_TYPE="webdav"
SERVER_URL="${dav_url}"
MOUNT_POINT="${mount_point}"
MOUNT_MODE="${mount_mode}"
WEBDAV_USER="${dav_user}"
CRED_FILE="${CREDENTIALS_DIR}/${mount_name}.cred"
UID="${uid_val}"
GID="${gid_val}"
EOF
    chmod 600 "$cfg_file"

    # 配置 davfs2 缓存和锁（避免 WebDAV 卡死）
    local davfs_cache="/var/cache/davfs2/${mount_name}"
    mkdir -p "$davfs_cache"
    chown root:root "$davfs_cache"

    # davfs2 全局配置优化
    if [[ -f /etc/davfs2/davfs2.conf ]]; then
        # 确保不会因为锁文件卡住
        sed -i 's/^# *use_locks.*/use_locks 0/' /etc/davfs2/davfs2.conf 2>/dev/null || true
        sed -i 's/^use_locks.*/use_locks 0/' /etc/davfs2/davfs2.conf 2>/dev/null || true

        # 增加超时时间
        grep -q "^Timeout" /etc/davfs2/davfs2.conf 2>/dev/null && \
            sed -i 's/^Timeout.*/Timeout 30/' /etc/davfs2/davfs2.conf 2>/dev/null || \
            echo "Timeout 30" >> /etc/davfs2/davfs2.conf

        # 重试次数
        grep -q "^RetryCount" /etc/davfs2/davfs2.conf 2>/dev/null && \
            sed -i 's/^RetryCount.*/RetryCount 5/' /etc/davfs2/davfs2.conf 2>/dev/null || \
            echo "RetryCount 5" >> /etc/davfs2/davfs2.conf
    fi

    # 创建 systemd 单元
    create_webdav_systemd "$mount_name" "$dav_url" "$mount_point" "$mount_mode" "$uid_val" "$gid_val"

    ok "WebDAV 挂载配置创建完成"
    echo ""

    echo -e "  ${GREEN}${BOLD}● WebDAV 挂载已配置！${NC}"
    echo -e "  ${BLUE}挂载点：${NC}${mount_point}"
    echo -e "  ${YELLOW}提示：automount 模式下，首次访问 ${mount_point} 时才会触发连接${NC}"

    sep
}

#-------------------- 创建 WebDAV systemd 单元 --------------------
create_webdav_systemd() {
    local name=$1
    local dav_url=$2
    local mount_point=$3
    local mode=$4
    local uid=$5
    local gid=$6

    local escaped_mp=$(systemd-escape --path "$mount_point")
    local mount_unit="${RECONNECT_TIMER_DIR}/${escaped_mp}.mount"
    local automount_unit="${RECONNECT_TIMER_DIR}/${escaped_mp}.automount"

    local options="uid=${uid},gid=${gid},file_mode=0664,dir_mode=0775,_netdev,nofail"

    # mount 单元
    cat > "$mount_unit" <<EOF
[Unit]
Description=Mount WebDAV: ${name} -> ${mount_point}
After=network-online.target
Wants=network-online.target

[Mount]
What=${dav_url}
Where=${mount_point}
Type=davfs
Options=${options}
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF

    # automount 单元
    cat > "$automount_unit" <<EOF
[Unit]
Description=Automount WebDAV: ${name} -> ${mount_point}

[Automount]
Where=${mount_point}
TimeoutIdleSec=300
EOF

    systemctl daemon-reload

    if [[ "$mode" == "1" ]]; then
        systemctl enable "${escaped_mp}.automount" 2>/dev/null
        systemctl restart "${escaped_mp}.automount" 2>/dev/null || true
    else
        systemctl enable "${escaped_mp}.mount" 2>/dev/null
        systemctl restart "${escaped_mp}.mount" 2>/dev/null || true
    fi
}

#-------------------- 功能 3：手动挂载全部 --------------------
mount_all() {
    sep
    echo -e "${BOLD}              手动挂载全部${NC}"
    sep
    echo ""

    if [[ ! -d "$MOUNT_CONFIG_DIR" ]] || [[ -z "$(ls "$MOUNT_CONFIG_DIR"/*.conf 2>/dev/null)" ]]; then
        warn "暂无挂载配置"
        return
    fi

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        source "$cfg_file"

        local name=$(basename "$cfg_file" .conf)

        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            info "[${name}] 已挂载，跳过"
            continue
        fi

        info "[${name}] 正在挂载..."

        if [[ "$MOUNT_TYPE" == "smb" ]]; then
            mount_smb_now "$cfg_file"
        elif [[ "$MOUNT_TYPE" == "webdav" ]]; then
            mount_webdav_now "$cfg_file"
        fi
    done

    echo ""
    ok "全部挂载操作完成"
    sep
}

#-------------------- 功能 4：手动卸载全部 --------------------
umount_all() {
    sep
    echo -e "${BOLD}              手动卸载全部${NC}"
    sep
    echo ""

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        source "$cfg_file"

        local name=$(basename "$cfg_file" .conf)

        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            info "[${name}] 正在卸载 ${MOUNT_POINT}..."
            umount -l "$MOUNT_POINT" 2>/dev/null && ok "[${name}] 已卸载" || warn "[${name}] 卸载失败"
        else
            info "[${name}] 未挂载，跳过"
        fi
    done

    echo ""
    ok "全部卸载操作完成"
    sep
}

#-------------------- SMB 立即挂载 --------------------
mount_smb_now() {
    local cfg_file=$1
    source "$cfg_file"

    local options="uid=${UID},gid=${GID},file_mode=${FILE_MODE},dir_mode=${DIR_MODE},iocharset=utf8,vers=3.0,_netdev"

    if [[ -n "$SMB_USER" && -f "$CRED_FILE" ]]; then
        options="${options},credentials=${CRED_FILE}"
    fi

    if mount -t cifs "$SERVER_URL" "$MOUNT_POINT" -o "$options" 2>/dev/null; then
        ok "SMB 挂载成功: ${MOUNT_POINT}"
    else
        fail "SMB 挂载失败: ${MOUNT_POINT}"
    fi
}

#-------------------- WebDAV 立即挂载 --------------------
mount_webdav_now() {
    local cfg_file=$1
    source "$cfg_file"

    if mount -t davfs "$SERVER_URL" "$MOUNT_POINT" 2>/dev/null; then
        ok "WebDAV 挂载成功: ${MOUNT_POINT}"
    else
        fail "WebDAV 挂载失败: ${MOUNT_POINT}"
    fi
}

#-------------------- 功能 5：单个挂载/卸载 --------------------
toggle_single_mount() {
    sep
    echo -e "${BOLD}              单个挂载点操作${NC}"
    sep
    echo ""

    if [[ ! -d "$MOUNT_CONFIG_DIR" ]] || [[ -z "$(ls "$MOUNT_CONFIG_DIR"/*.conf 2>/dev/null)" ]]; then
        warn "暂无挂载配置"
        return
    fi

    local idx=1
    declare -A cfg_map

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        source "$cfg_file"
        local name=$(basename "$cfg_file" .conf)
        local status_icon="○"
        mountpoint -q "$MOUNT_POINT" 2>/dev/null && status_icon="●"

        echo -e "  ${CYAN}[$idx]${NC} ${status_icon} ${name} (${MOUNT_TYPE}) → ${MOUNT_POINT}"
        cfg_map[$idx]="$cfg_file"
        idx=$((idx + 1))
    done

    echo ""
    echo -e "  ${CYAN} a)${NC} 挂载全部    ${CYAN} u)${NC} 卸载全部"
    echo ""
    echo -n "  输入编号挂载/卸载（或 Enter 返回）: "
    read -r choice

    if [[ -z "$choice" ]]; then
        return
    fi

    if [[ "$choice" == "a" ]]; then
        mount_all
        return
    fi

    if [[ "$choice" == "u" ]]; then
        umount_all
        return
    fi

    local cfg_file="${cfg_map[$choice]}"
    if [[ -z "$cfg_file" ]]; then
        warn "无效选择"
        return
    fi

    source "$cfg_file"

    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        info "卸载 ${MOUNT_POINT}..."
        umount -l "$MOUNT_POINT" 2>/dev/null && ok "已卸载" || fail "卸载失败"
    else
        info "挂载 ${MOUNT_POINT}..."
        if [[ "$MOUNT_TYPE" == "smb" ]]; then
            mount_smb_now "$cfg_file"
        else
            mount_webdav_now "$cfg_file"
        fi
    fi

    sep
}

#-------------------- 功能 6：测试挂载连接 --------------------
test_connection() {
    sep
    echo -e "${BOLD}              测试挂载连接${NC}"
    sep
    echo ""

    if [[ ! -d "$MOUNT_CONFIG_DIR" ]] || [[ -z "$(ls "$MOUNT_CONFIG_DIR"/*.conf 2>/dev/null)" ]]; then
        warn "暂无挂载配置"
        return
    fi

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        source "$cfg_file"

        local name=$(basename "$cfg_file" .conf)
        local target=""

        if [[ "$MOUNT_TYPE" == "smb" ]]; then
            target="${SERVER_ADDR}:${PORT}"
            echo -n "  [${name}] SMB ${target} ... "
            # 测试 SMB 端口连通性
            if timeout 5 bash -c "echo >/dev/tcp/${SERVER_ADDR}/${PORT}" 2>/dev/null; then
                echo -e "${GREEN}连通 ✓${NC}"
            else
                echo -e "${RED}不通 ✗${NC}"
            fi
        elif [[ "$MOUNT_TYPE" == "webdav" ]]; then
            target="${SERVER_URL}"
            echo -n "  [${name}] WebDAV ${target} ... "
            local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$target" 2>/dev/null)
            if [[ "$http_code" =~ ^(200|301|302|401|403|405)$ ]]; then
                echo -e "${GREEN}响应 ${http_code} ✓${NC}"
            elif [[ -n "$http_code" ]]; then
                echo -e "${YELLOW}响应 ${http_code}（可能正常）${NC}"
            else
                echo -e "${RED}无响应 ✗${NC}"
            fi
        fi
    done

    echo ""
    sep
}

#-------------------- 功能 7：配置断线自动重连 --------------------
setup_reconnect() {
    sep
    echo -e "${BOLD}              配置断线自动重连${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}重连机制说明：${NC}"
    echo -e "  ${GREEN}● 使用 systemd timer 每分钟检测一次服务器在线状态${NC}"
    echo -e "  ${GREEN}● 服务器不在线时静默等待，不尝试挂载${NC}"
    echo -e "  ${GREEN}● 服务器上线后且未挂载时，自动连接并挂载${NC}"
    echo -e "  ${GREEN}● 已挂载但服务器掉线时，自动卸载并等待服务器恢复${NC}"
    echo -e "  ${GREEN}● 最多重试 3 次，避免无限循环${NC}"
    echo -e "  ${GREEN}● 使用 lazy umount（umount -l）避免卡死${NC}"
    echo ""

    echo -n "  重连检测间隔（分钟，默认 1）: "
    read -r interval
    interval="${interval:-1}"

    echo -n "  服务器检测超时（秒，默认 5）: "
    read -r detect_timeout
    detect_timeout="${detect_timeout:-5}"

    echo -n "  每次重试等待秒数（默认 10）: "
    read -r retry_wait
    retry_wait="${retry_wait:-10}"

    echo -n "  最大重试次数（默认 3）: "
    read -r max_retries
    max_retries="${max_retries:-3}"

    info "创建重连脚本..."

    # 创建重连脚本（带服务器在线检测）
    cat > "$RECONNECT_SCRIPT" <<'RECONNECT_EOF'
#!/bin/bash
#=============================================================================
# 磁盘挂载断线自动重连脚本（由 systemd timer 调用）
# 功能：
#   1. 检测服务器是否在线（SMB 探测 445 端口 / WebDAV HTTP 探测）
#   2. 服务器不在线时静默等待
#   3. 服务器上线且未挂载时自动挂载
#   4. 已挂载但服务器掉线时自动卸载
#   5. 最多重试 3 次
#=============================================================================

MOUNT_CONFIG_DIR="/etc/disk_mount_configs"
LOG_TAG="disk-mount-reconnect"

log_info()  { logger -t "$LOG_TAG" "[信息] $*"; }
log_warn()  { logger -t "$LOG_TAG" "[警告] $*"; }
log_error() { logger -t "$LOG_TAG" "[错误] $*"; }
log_debug() { logger -t "$LOG_TAG" "[调试] $*"; }

MAX_RETRIES=${MAX_RETRIES}
RETRY_WAIT=${RETRY_WAIT}
DETECT_TIMEOUT=${DETECT_TIMEOUT}

# 检测服务器是否在线
# SMB: 探测 TCP 端口
# WebDAV: HTTP 请求检测
is_server_online() {
    local type="$1"
    local addr="$2"
    local port="$3"
    local url="$4"

    if [[ "$type" == "smb" ]]; then
        # SMB: 探测 TCP 445 端口
        if timeout "$DETECT_TIMEOUT" bash -c "exec 3<>/dev/tcp/${addr}/${port}; exec 3<&-; exec 3>&-" 2>/dev/null; then
            return 0
        fi
    elif [[ "$type" == "webdav" ]]; then
        # WebDAV: curl 探测
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$DETECT_TIMEOUT" --max-time "$((DETECT_TIMEOUT + 3))" "$url" 2>/dev/null)
        if [[ "$http_code" =~ ^(200|301|302|401|403|405|207)$ ]]; then
            return 0
        fi
    fi

    return 1
}

# 主循环
for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
    [ -f "$cfg_file" ] || continue

    source "$cfg_file"
    name=$(basename "$cfg_file" .conf)

    # 检测服务器在线状态
    local server_online=false
    if is_server_online "$MOUNT_TYPE" "$SERVER_ADDR" "${PORT:-445}" "$SERVER_URL"; then
        server_online=true
    fi

    # 判断挂载点是否已挂载
    local is_mounted=false
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        is_mounted=true
    fi

    if [[ "$server_online" == "false" && "$is_mounted" == "true" ]]; then
        # 服务器掉线但本地仍显示挂载，执行卸载
        log_warn "[$name] 服务器离线，执行卸载: $MOUNT_POINT"
        umount -l "$MOUNT_POINT" 2>/dev/null || true
        continue
    fi

    if [[ "$server_online" == "false" && "$is_mounted" == "false" ]]; then
        # 服务器不在线且未挂载，静默等待（不记录日志避免刷屏）
        log_debug "[$name] 服务器离线，等待上线..."
        continue
    fi

    if [[ "$server_online" == "true" && "$is_mounted" == "true" ]]; then
        # 服务器在线且已挂载，一切正常
        log_debug "[$name] 服务器在线，挂载正常: $MOUNT_POINT"
        continue
    fi

    # 服务器在线但未挂载，需要挂载
    log_info "[$name] 服务器上线，正在挂载: $MOUNT_POINT"

    # 清理残留
    umount -l "$MOUNT_POINT" 2>/dev/null || true
    sleep 1

    retry=0
    success=false

    while [[ $retry -lt $MAX_RETRIES ]]; do
        retry=$((retry + 1))

        if [[ "$MOUNT_TYPE" == "smb" ]]; then
            options="uid=${UID},gid=${GID},file_mode=${FILE_MODE},dir_mode=${DIR_MODE},iocharset=utf8,vers=3.0,_netdev"
            [ -n "$SMB_USER" ] && [ -f "$CRED_FILE" ] && options="${options},credentials=${CRED_FILE}"

            if mount -t cifs "$SERVER_URL" "$MOUNT_POINT" -o "$options" 2>/dev/null; then
                log_info "[$name] SMB 挂载成功 (第${retry}次尝试)"
                success=true
                break
            fi
        elif [[ "$MOUNT_TYPE" == "webdav" ]]; then
            if mount -t davfs "$SERVER_URL" "$MOUNT_POINT" 2>/dev/null; then
                log_info "[$name] WebDAV 挂载成功 (第${retry}次尝试)"
                success=true
                break
            fi
        fi

        log_warn "[$name] 第${retry}次挂载失败，等待 ${RETRY_WAIT} 秒后重试..."
        sleep "$RETRY_WAIT"
    done

    if [[ "$success" != "true" ]]; then
        log_error "[$name] 挂载失败（已尝试 ${MAX_RETRIES} 次），将在下次检测时再试"
    fi
done
RECONNECT_EOF

    # 替换变量
    sed -i "s/\${MAX_RETRIES}/${max_retries}/g" "$RECONNECT_SCRIPT"
    sed -i "s/\${RETRY_WAIT}/${retry_wait}/g" "$RECONNECT_SCRIPT"
    sed -i "s/\${DETECT_TIMEOUT}/${detect_timeout}/g" "$RECONNECT_SCRIPT"

    chmod +x "$RECONNECT_SCRIPT"
    ok "重连脚本已创建: ${RECONNECT_SCRIPT}"

    # 创建 systemd service
    cat > "${RECONNECT_TIMER_DIR}/disk-mount-reconnect.service" <<EOF
[Unit]
Description=Disk Mount Reconnect Service (server online detection)
After=network-online.target

[Service]
Type=oneshot
ExecStart=${RECONNECT_SCRIPT}
TimeoutStartSec=180
EOF

    # 创建 systemd timer
    cat > "${RECONNECT_TIMER_DIR}/disk-mount-reconnect.timer" <<EOF
[Unit]
Description=Disk Mount Reconnect Timer (check every ${interval} min)

[Timer]
OnBootSec=1min
OnUnitActiveSec=${interval}min
Persistent=true
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable disk-mount-reconnect.timer 2>/dev/null
    systemctl start disk-mount-reconnect.timer 2>/dev/null

    ok "断线重连服务已启动（每 ${interval} 分钟检测一次服务器）"

    echo ""
    echo -e "  ${GREEN}${BOLD}● 断线自动重连已配置！${NC}"
    echo -e "  ${BLUE}检测间隔：${NC}每 ${interval} 分钟"
    echo -e "  ${BLUE}检测超时：${NC}${detect_timeout} 秒"
    echo -e "  ${BLUE}重试次数：${NC}最多 ${max_retries} 次"
    echo -e "  ${BLUE}重试间隔：${NC}${retry_wait} 秒"
    echo -e "  ${YELLOW}查看日志：journalctl -u disk-mount-reconnect -f${NC}"

    sep
}

#-------------------- 功能 8：查看重连日志 --------------------
show_reconnect_log() {
    sep
    echo -e "${BOLD}              断线重连日志（最近 30 条）${NC}"
    sep
    echo ""

    journalctl -u disk-mount-reconnect -n 30 --no-pager 2>/dev/null || warn "暂无日志"

    sep
}

#-------------------- 功能 9：启用/禁用重连服务 --------------------
toggle_reconnect_service() {
    sep
    echo -e "${BOLD}              重连服务管理${NC}"
    sep
    echo ""

    local is_active=false
    if systemctl is-active --quiet disk-mount-reconnect.timer 2>/dev/null; then
        is_active=true
    fi

    echo -e "  ${BLUE}当前状态：${NC}$([ "$is_active" == "true" ] && echo "${GREEN}运行中${NC}" || echo "${YELLOW}未运行${NC}")"
    echo ""

    echo -e "  ${CYAN} 1)${NC} 启动重连服务"
    echo -e "  ${CYAN} 2)${NC} 停止重连服务"
    echo -e "  ${CYAN} 3)${NC} 立即执行一次重连检测"
    echo ""
    echo -n "请选择: "
    read -r choice

    case "$choice" in
        1)
            systemctl enable --now disk-mount-reconnect.timer 2>/dev/null
            ok "重连服务已启动"
            ;;
        2)
            systemctl stop --disable disk-mount-reconnect.timer 2>/dev/null
            ok "重连服务已停止"
            ;;
        3)
            systemctl start disk-mount-reconnect.service 2>/dev/null
            ok "重连检测已执行"
            echo ""
            echo -e "  ${YELLOW}最近日志：${NC}"
            journalctl -u disk-mount-reconnect -n 10 --no-pager 2>/dev/null
            ;;
        *)
            info "已取消"
            ;;
    esac

    sep
}

#-------------------- 功能 10：查看所有配置 --------------------
show_all_configs() {
    sep
    echo -e "${BOLD}              所有挂载配置${NC}"
    sep
    echo ""

    if [[ ! -d "$MOUNT_CONFIG_DIR" ]] || [[ -z "$(ls "$MOUNT_CONFIG_DIR"/*.conf 2>/dev/null)" ]]; then
        warn "暂无挂载配置"
        sep
        return
    fi

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        source "$cfg_file"

        local name=$(basename "$cfg_file" .conf)
        local mount_status="${RED}未挂载${NC}"
        mountpoint -q "$MOUNT_POINT" 2>/dev/null && mount_status="${GREEN}已挂载${NC}"

        sep_s
        echo -e "  ${BOLD}${CYAN}[${name}]${NC}"
        echo -e "  ${BLUE}类型    ：${NC}${MOUNT_TYPE}"
        echo -e "  ${BLUE}服务器  ：${NC}${SERVER_URL}"
        echo -e "  ${BLUE}挂载点  ：${NC}${MOUNT_POINT}"
        echo -e "  ${BLUE}状态    ：${NC}${mount_status}"
        echo -e "  ${BLUE}挂载方式：${NC}$([ "$MOUNT_MODE" == "1" ] && echo "automount" || echo "mount")"
        echo -e "  ${BLUE}UID:GID ：${NC}${UID}:${GID}"

        # 显示 systemd 单元状态
        local escaped_mp=$(systemd-escape --path "$MOUNT_POINT")
        local unit_status=""
        if systemctl is-enabled "${escaped_mp}.automount" 2>/dev/null | grep -q "enabled"; then
            unit_status="${GREEN}automount 已启用${NC}"
        elif systemctl is-enabled "${escaped_mp}.mount" 2>/dev/null | grep -q "enabled"; then
            unit_status="${GREEN}mount 已启用${NC}"
        else
            unit_status="${YELLOW}未启用 systemd 单元${NC}"
        fi
        echo -e "  ${BLUE}Systemd ：${NC}${unit_status}"

        sep_s
        echo ""
    done

    sep
}

#-------------------- 功能 11：删除挂载配置 --------------------
delete_mount_config() {
    sep
    echo -e "${BOLD}              删除挂载配置${NC}"
    sep
    echo ""

    if [[ ! -d "$MOUNT_CONFIG_DIR" ]] || [[ -z "$(ls "$MOUNT_CONFIG_DIR"/*.conf 2>/dev/null)" ]]; then
        warn "暂无挂载配置"
        return
    fi

    local idx=1
    declare -A cfg_map

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        local name=$(basename "$cfg_file" .conf)
        echo -e "  ${CYAN}[$idx]${NC} ${name}"
        cfg_map[$idx]="$cfg_file"
        idx=$((idx + 1))
    done

    echo ""
    echo -n "  输入要删除的编号（或 Enter 取消）: "
    read -r del_idx

    if [[ -z "$del_idx" || -z "${cfg_map[$del_idx]}" ]]; then
        info "已取消"
        return
    fi

    local cfg_file="${cfg_map[$del_idx]}"
    source "$cfg_file"
    local name=$(basename "$cfg_file" .conf)

    echo -e "  ${RED}将删除：${NC}"
    echo -e "  ${YELLOW}配置文件：${NC}${cfg_file}"
    echo -e "  ${YELLOW}凭据文件：${NC}${CRED_FILE:-无}"
    echo -e "  ${YELLOW}挂载点  ：${NC}${MOUNT_POINT}（保留目录，仅卸载）"
    echo ""
    echo -n "  确认删除？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "正在删除..."

    # 卸载
    mountpoint -q "$MOUNT_POINT" 2>/dev/null && umount -l "$MOUNT_POINT" 2>/dev/null

    # 禁用 systemd 单元
    local escaped_mp=$(systemd-escape --path "$MOUNT_POINT")
    systemctl disable "${escaped_mp}.automount" 2>/dev/null || true
    systemctl disable "${escaped_mp}.mount" 2>/dev/null || true
    systemctl stop "${escaped_mp}.automount" 2>/dev/null || true
    systemctl stop "${escaped_mp}.mount" 2>/dev/null || true
    rm -f "${RECONNECT_TIMER_DIR}/${escaped_mp}.automount"
    rm -f "${RECONNECT_TIMER_DIR}/${escaped_mp}.mount"

    # 删除配置和凭据
    rm -f "$cfg_file"
    [[ -f "$CRED_FILE" ]] && rm -f "$CRED_FILE"

    # 清理 davfs2 secrets 中的条目
    if [[ "$MOUNT_TYPE" == "webdav" && -f /etc/davfs2/secrets ]]; then
        sed -i "\|${MOUNT_POINT}|d" /etc/davfs2/secrets
    fi

    systemctl daemon-reload

    ok "挂载配置 [${name}] 已删除"

    sep
}

#-------------------- 功能 12：修改挂载配置 --------------------
edit_mount_config() {
    sep
    echo -e "${BOLD}              修改挂载配置${NC}"
    sep
    echo ""

    if [[ ! -d "$MOUNT_CONFIG_DIR" ]] || [[ -z "$(ls "$MOUNT_CONFIG_DIR"/*.conf 2>/dev/null)" ]]; then
        warn "暂无挂载配置"
        return
    fi

    local idx=1
    declare -A cfg_map

    for cfg_file in "$MOUNT_CONFIG_DIR"/*.conf; do
        [[ -f "$cfg_file" ]] || continue
        source "$cfg_file"
        local name=$(basename "$cfg_file" .conf)
        echo -e "  ${CYAN}[$idx]${NC} ${name} (${MOUNT_TYPE}) → ${SERVER_URL}"
        cfg_map[$idx]="$cfg_file"
        idx=$((idx + 1))
    done

    echo ""
    echo -n "  输入要修改的编号（或 Enter 取消）: "
    read -r edit_idx

    if [[ -z "$edit_idx" || -z "${cfg_map[$edit_idx]}" ]]; then
        info "已取消"
        return
    fi

    local cfg_file="${cfg_map[$edit_idx]}"
    source "$cfg_file"
    local name=$(basename "$cfg_file" .conf)

    echo ""
    echo -e "  ${BOLD}选择要修改的项目：${NC}"
    echo -e "  ${CYAN} 1)${NC} 服务器地址"
    echo -e "  ${CYAN} 2)${NC} 用户名和密码"
    echo -e "  ${CYAN} 3)${NC} 挂载点路径"
    echo -e "  ${CYAN} 4)${NC} 挂载方式（automount/mount）"
    echo ""
    echo -n "请选择: "
    read -r edit_choice

    case "$edit_choice" in
        1)
            echo -n "  新的服务器地址: "
            read -r new_url
            sed -i "s|^SERVER_URL=.*|SERVER_URL=\"${new_url}\"|" "$cfg_file"

            # 更新 systemd 单元
            local escaped_mp=$(systemd-escape --path "$MOUNT_POINT")
            systemctl stop "${escaped_mp}.automount" 2>/dev/null || true
            systemctl stop "${escaped_mp}.mount" 2>/dev/null || true

            if [[ "$MOUNT_TYPE" == "smb" ]]; then
                create_smb_systemd "$name" "$new_url" "$MOUNT_POINT" "$PORT" "$MOUNT_MODE" "$UID" "$GID" "$FILE_MODE" "$DIR_MODE" "$SMB_USER"
            else
                create_webdav_systemd "$name" "$new_url" "$MOUNT_POINT" "$MOUNT_MODE" "$UID" "$GID"
            fi

            ok "服务器地址已更新"
            ;;
        2)
            echo -n "  新用户名: "
            read -r new_user
            echo -n "  新密码: "
            read -r -s new_pass
            echo ""

            if [[ "$MOUNT_TYPE" == "smb" ]]; then
                local cred_file="${CREDENTIALS_DIR}/${name}.cred"
                cat > "$cred_file" <<EOF
username=${new_user}
password=${new_pass}
EOF
                chmod 600 "$cred_file"
                sed -i "s|^SMB_USER=.*|SMB_USER=\"${new_user}\"|" "$cfg_file"
            else
                # 更新 davfs2 secrets
                sed -i "\|${MOUNT_POINT}|d" /etc/davfs2/secrets
                echo "${MOUNT_POINT} ${new_user} \"${new_pass}\"" >> /etc/davfs2/secrets
                chmod 600 /etc/davfs2/secrets
                sed -i "s|^WEBDAV_USER=.*|WEBDAV_USER=\"${new_user}\"|" "$cfg_file"
            fi

            ok "用户名和密码已更新"
            ;;
        3)
            echo -e "  ${YELLOW}修改挂载点需要重建 systemd 单元${NC}"
            echo -n "  新的挂载点路径: "
            read -r new_mp
            mkdir -p "$new_mp"

            # 卸载旧的
            mountpoint -q "$MOUNT_POINT" 2>/dev/null && umount -l "$MOUNT_POINT" 2>/dev/null

            # 删除旧的 systemd 单元
            local old_esc=$(systemd-escape --path "$MOUNT_POINT")
            systemctl disable "${old_esc}.automount" 2>/dev/null || true
            systemctl disable "${old_esc}.mount" 2>/dev/null || true
            rm -f "${RECONNECT_TIMER_DIR}/${old_esc}.automount"
            rm -f "${RECONNECT_TIMER_DIR}/${old_esc}.mount"

            # 更新配置
            sed -i "s|^MOUNT_POINT=.*|MOUNT_POINT=\"${new_mp}\"|" "$cfg_file"

            # 重建 systemd 单元
            source "$cfg_file"
            if [[ "$MOUNT_TYPE" == "smb" ]]; then
                create_smb_systemd "$name" "$SERVER_URL" "$new_mp" "$PORT" "$MOUNT_MODE" "$UID" "$GID" "$FILE_MODE" "$DIR_MODE" "$SMB_USER"
            else
                create_webdav_systemd "$name" "$SERVER_URL" "$new_mp" "$MOUNT_MODE" "$UID" "$GID"
            fi

            ok "挂载点已更新为 ${new_mp}"
            ;;
        4)
            echo -e "  ${CYAN} 1)${NC} automount（推荐）"
            echo -e "  ${CYAN} 2)${NC} mount"
            echo -n "  选择挂载方式: "
            read -r new_mode
            sed -i "s|^MOUNT_MODE=.*|MOUNT_MODE=\"${new_mode}\"|" "$cfg_file"

            source "$cfg_file"
            local escaped_mp=$(systemd-escape --path "$MOUNT_POINT")
            systemctl disable "${escaped_mp}.automount" 2>/dev/null || true
            systemctl disable "${escaped_mp}.mount" 2>/dev/null || true

            if [[ "$MOUNT_TYPE" == "smb" ]]; then
                create_smb_systemd "$name" "$SERVER_URL" "$MOUNT_POINT" "$PORT" "$new_mode" "$UID" "$GID" "$FILE_MODE" "$DIR_MODE" "$SMB_USER"
            else
                create_webdav_systemd "$name" "$SERVER_URL" "$MOUNT_POINT" "$new_mode" "$UID" "$GID"
            fi

            ok "挂载方式已更新"
            ;;
        *)
            info "已取消"
            ;;
    esac

    sep
}

#-------------------- 主循环 --------------------
main() {
    check_root

    # 初始化配置目录
    mkdir -p "$MOUNT_CONFIG_DIR" "$CREDENTIALS_DIR"

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1) add_smb_mount ;;
            2) add_webdav_mount ;;
            3) mount_all ;;
            4) umount_all ;;
            5) toggle_single_mount ;;
            6) test_connection ;;
            7) setup_reconnect ;;
            8) show_reconnect_log ;;
            9) toggle_reconnect_service ;;
            10) show_all_configs ;;
            11) delete_mount_config ;;
            12) edit_mount_config ;;
            0|q|Q)
                echo ""
                info "退出磁盘挂载管理脚本"
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