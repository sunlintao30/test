#!/bin/bash
#=============================================================================
# 服务器运维脚本工具集 - 主菜单
# 功能：统一入口，调用各分支运维脚本
# 用法：chmod +x main.sh && sudo ./main.sh
#       curl -fsSL <RAW_URL>/main.sh | sudo bash  （管道方式也支持交互）
#=============================================================================

# 管道执行（curl|bash）时 stdin 被脚本内容占用，交互式菜单无法正常输入
# 检测到管道模式时，自动下载脚本到本地并在新的终端环境中执行
# 交互式菜单脚本不使用 set -e，避免 read 偶发返回非 0 时误退出
detect_and_run() {
    if [[ -t 0 ]]; then
        return 0
    fi

    cat <<'HEADER'

================================================
服务器运维脚本工具集
================================================

检测到管道执行模式（curl | bash），正在为您准备交互式环境...
HEADER

    local tmp_script="/tmp/ops_main.sh"
    local script_url="https://raw.githubusercontent.com/sunlintao30/test/main/main.sh"
    local mirror_url="https://mirror.ghproxy.com/https://raw.githubusercontent.com/sunlintao30/test/main/main.sh"
    local downloaded=0

    echo ""
    echo "正在下载脚本（GitHub 源）..."
    if command -v curl &>/dev/null; then
        if curl -fsSL --connect-timeout 10 --max-time 30 "$script_url" -o "$tmp_script" 2>/dev/null && [[ -s "$tmp_script" ]]; then
            downloaded=1
        else
            echo "GitHub 源下载超时，尝试国内加速源..."
            if curl -fsSL --connect-timeout 10 --max-time 30 "$mirror_url" -o "$tmp_script" 2>/dev/null && [[ -s "$tmp_script" ]]; then
                downloaded=1
            fi
        fi
    elif command -v wget &>/dev/null; then
        if wget -q --timeout=10 --tries=1 "$script_url" -O "$tmp_script" 2>/dev/null && [[ -s "$tmp_script" ]]; then
            downloaded=1
        else
            echo "GitHub 源下载超时，尝试国内加速源..."
            if wget -q --timeout=10 --tries=1 "$mirror_url" -O "$tmp_script" 2>/dev/null && [[ -s "$tmp_script" ]]; then
                downloaded=1
            fi
        fi
    else
        echo "错误：未找到 curl 或 wget，请先安装后再运行"
        exit 1
    fi

    if [[ $downloaded -eq 1 ]]; then
        chmod +x "$tmp_script"
        echo "下载完成，正在启动主菜单..."
        echo ""
        exec bash "$tmp_script" "$@"
    else
        cat <<EOF

下载失败，请使用以下任一方式运行：

方式一：下载后执行（推荐）
  curl -fsSL $script_url -o /tmp/main.sh
  chmod +x /tmp/main.sh && sudo /tmp/main.sh

方式二：国内加速地址
  curl -fsSL $mirror_url -o /tmp/main.sh
  chmod +x /tmp/main.sh && sudo /tmp/main.sh

方式三：本地克隆
  git clone https://github.com/sunlintao30/test.git ~/ops-scripts
  cd ~/ops-scripts && chmod +x *.sh && sudo ./main.sh
EOF
        exit 1
    fi
}

detect_and_run "$@"

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

#-------------------- 脚本目录 & 在线地址 --------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 仓库在线地址（GitHub raw）
REPO_RAW="https://raw.githubusercontent.com/sunlintao30/test/main"
REPO_URL="https://github.com/sunlintao30/test"

#-------------------- 检查 root --------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        warn "建议使用 root 权限运行以避免权限问题：sudo $0"
        echo -n "  仍要以当前用户继续？(y/N): "
        read -r confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
        SUDO="sudo"
    else
        SUDO=""
    fi
}

#-------------------- 下载文件（带超时和国内加速） --------------------
# 参数：$1=URL  $2=保存路径
# 返回：0成功 1失败
download_file() {
    local url="$1"
    local output="$2"
    local mirror_url=""

    # 如果是 GitHub raw，生成国内加速地址
    if [[ "$url" == *"raw.githubusercontent.com"* ]]; then
        mirror_url="https://mirror.ghproxy.com/${url}"
    fi

    if command -v curl &>/dev/null; then
        if curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$output" 2>/dev/null && [[ -s "$output" ]]; then
            return 0
        elif [[ -n "$mirror_url" ]]; then
            warn "GitHub 源下载慢，尝试国内加速源..."
            if curl -fsSL --connect-timeout 10 --max-time 30 "$mirror_url" -o "$output" 2>/dev/null && [[ -s "$output" ]]; then
                ok "国内加速源下载成功"
                return 0
            fi
        fi
    elif command -v wget &>/dev/null; then
        if wget -q --timeout=10 --tries=1 "$url" -O "$output" 2>/dev/null && [[ -s "$output" ]]; then
            return 0
        elif [[ -n "$mirror_url" ]]; then
            warn "GitHub 源下载慢，尝试国内加速源..."
            if wget -q --timeout=10 --tries=1 "$mirror_url" -O "$output" 2>/dev/null && [[ -s "$output" ]]; then
                ok "国内加速源下载成功"
                return 0
            fi
        fi
    fi

    return 1
}

#-------------------- 调用分支脚本 --------------------
# 参数：$1=脚本文件名
# 优先本地执行；本地不存在时从在线地址下载并执行
run_script() {
    local script="$1"
    local local_path="${SCRIPT_DIR}/${script}"
    local remote_url="${REPO_RAW}/${script}"

    sep

    # 情况 1：本地存在该脚本，直接执行
    if [[ -f "$local_path" ]]; then
        if [[ ! -x "$local_path" ]]; then
            info "添加执行权限：chmod +x $script"
            chmod +x "$local_path"
        fi
        info "启动 ${BOLD}${script}${NC} ${BLUE}（本地）${NC} ..."
        sep
        echo ""
        $SUDO "$local_path" || warn "$script 退出（code=$?）"
    else
        # 情况 2：本地不存在，从在线地址下载执行
        if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
            error "未找到 curl 或 wget，无法下载 $script"
            info "请先安装：apt install -y curl wget"
            return 1
        fi

        info "本地未找到 ${script}，从在线地址下载..."
        info "${CYAN}${remote_url}${NC}"
        echo ""

        # 下载到临时文件并执行
        local tmp_script
        tmp_script=$(mktemp "/tmp/${script%.sh}.XXXXXX.sh")
        if download_file "$remote_url" "$tmp_script"; then
            chmod +x "$tmp_script"
            sep
            info "启动 ${BOLD}${script}${NC} ${BLUE}（在线）${NC} ..."
            sep
            echo ""
            $SUDO bash "$tmp_script" || warn "$script 退出（code=$?）"
        else
            error "下载失败：$remote_url"
            info "请检查网络连接或仓库地址是否正确"
            rm -f "$tmp_script"
            return 1
        fi
        rm -f "$tmp_script"
    fi

    echo ""
    sep
    info "返回主菜单，按回车继续..."
    read -r
}

#-------------------- 系统信息 --------------------
show_system_info() {
    local os_name="未知系统"
    [[ -f /etc/os-release ]] && . /etc/os-release && os_name="${PRETTY_NAME:-未知系统}"
    echo -e "  ${BLUE}系统：${NC}${CYAN}${os_name}${NC}"
    echo -e "  ${BLUE}内核：${NC}${CYAN}$(uname -r)${NC}  ${BLUE}架构：${NC}${CYAN}$(uname -m)${NC}"
    echo -e "  ${BLUE}主机：${NC}${CYAN}$(hostname)${NC}  ${BLUE}运行：${NC}${CYAN}$(uptime -p 2>/dev/null | sed 's/up //')${NC}"
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}          服务器运维脚本工具集 - 主菜单${NC}"
    sep
    echo ""
    show_system_info
    echo ""
    sep_s
    echo -e "  ${MAGENTA}本地目录：${NC}${CYAN}${SCRIPT_DIR}${NC}"
    echo -e "  ${MAGENTA}在线地址：${NC}${CYAN}${REPO_URL}${NC}"
    sep_s
    echo ""

    echo -e "  ${CYAN}【系统管理与优化】${NC}"
    echo -e "  ${CYAN} 1)${NC} 系统信息查看 & 测速 & 回程路由    ${MAGENTA}system_info.sh${NC}"
    echo -e "  ${CYAN} 2)${NC} Linux 系统优化（内核/网络/内存）  ${MAGENTA}linux_optimize.sh${NC}"
    echo -e "  ${CYAN} 3)${NC} SSH 安全管理（端口/加固/密钥）     ${MAGENTA}ssh_manager.sh${NC}"
    echo -e "  ${CYAN} 4)${NC} BBR 拥塞控制管理                  ${MAGENTA}bbr_manager.sh${NC}"
    echo -e "  ${CYAN} 5)${NC} 系统软件源 / Docker 镜像源切换    ${MAGENTA}change_mirror.sh${NC}"
    echo -e "  ${CYAN} 6)${NC} Docker 一键安装                   ${MAGENTA}install_docker.sh${NC}"
    echo ""

    echo -e "  ${CYAN}【面板管理】${NC}"
    echo -e "  ${CYAN} 7)${NC} 1Panel 管理面板                  ${MAGENTA}1panel_manager.sh${NC}"
    echo -e "  ${CYAN} 8)${NC} 3X-UI 代理面板（Xray 多协议）     ${MAGENTA}xui_manager.sh${NC}"
    echo ""

    echo -e "  ${CYAN}【网络与组网】${NC}"
    echo -e "  ${CYAN} 9)${NC} EasyTier 组网管理                ${MAGENTA}easytier_manager.sh${NC}"
    echo -e "  ${CYAN}10)${NC} Hysteria 2 代理部署              ${MAGENTA}hysteria_manager.sh${NC}"
    echo -e "  ${CYAN}11)${NC} MTProto Proxy 部署（Fake TLS）    ${MAGENTA}mtproxy.sh${NC}"
    echo ""

    echo -e "  ${CYAN}【磁盘与文件】${NC}"
    echo -e "  ${CYAN}12)${NC} 网络磁盘挂载（SMB/WebDAV）       ${MAGENTA}disk_mount.sh${NC}"
    echo -e "  ${CYAN}13)${NC} 文件共享服务器（SMB/NFS/FTP...）  ${MAGENTA}file_share.sh${NC}"
    echo -e "  ${CYAN}14)${NC} 文件同步（Syncthing/rclone...）   ${MAGENTA}file_sync.sh${NC}"
    echo -e "  ${CYAN}15)${NC} 远程下载工具（Aria2/qBt/Tr）      ${MAGENTA}download_manager.sh${NC}"
    echo ""

    echo -e "  ${CYAN}【固件编译】${NC}"
    echo -e "  ${CYAN}16)${NC} ImmortalWrt/OpenWrt 编译环境     ${MAGENTA}immortalwrt_build.sh${NC}"
    echo ""

    echo -e "  ${CYAN}【其他】${NC}"
    echo -e "  ${CYAN} a)${NC} 列出所有分支脚本"
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
}

#-------------------- 列出所有分支脚本 --------------------
list_all_scripts() {
    sep
    echo -e "${BOLD}              所有分支脚本列表${NC}"
    sep
    echo ""
    printf "  %-4s %-26s %-14s %s\n" "序号" "脚本文件" "分类" "来源"
    sep_s

    local idx=1
    local scripts=(
        "system_info.sh|系统管理与优化"
        "linux_optimize.sh|系统管理与优化"
        "ssh_manager.sh|系统管理与优化"
        "bbr_manager.sh|系统管理与优化"
        "change_mirror.sh|系统管理与优化"
        "install_docker.sh|系统管理与优化"
        "1panel_manager.sh|面板管理"
        "xui_manager.sh|面板管理"
        "easytier_manager.sh|网络与组网"
        "hysteria_manager.sh|网络与组网"
        "mtproxy.sh|网络与组网"
        "disk_mount.sh|磁盘与文件"
        "file_share.sh|磁盘与文件"
        "file_sync.sh|磁盘与文件"
        "download_manager.sh|磁盘与文件"
        "immortalwrt_build.sh|固件编译"
    )

    for item in "${scripts[@]}"; do
        local file="${item%%|*}"
        local cat="${item##*|}"
        local source=""
        if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
            source="${GREEN}本地${NC}"
        else
            source="${BLUE}在线${NC}"
        fi
        printf "  %-4s %-26s %-14s %b\n" "$idx" "$file" "$cat" "$source"
        idx=$((idx + 1))
    done

    echo ""
    sep_s
    echo -e "  ${MAGENTA}在线仓库：${NC}${CYAN}${REPO_URL}${NC}"
    echo -e "  ${MAGENTA}Raw 地址：${NC}${CYAN}${REPO_RAW}/<脚本名>.sh${NC}"
    sep
    info "按回车返回主菜单..."
    read -r
}

#-------------------- 主循环 --------------------
main() {
    check_root

    while true; do
        show_menu
        echo -n "请输入选项: "
        read -r choice
        echo ""
        case "$choice" in
            1)  run_script "system_info.sh" ;;
            2)  run_script "linux_optimize.sh" ;;
            3)  run_script "ssh_manager.sh" ;;
            4)  run_script "bbr_manager.sh" ;;
            5)  run_script "change_mirror.sh" ;;
            6)  run_script "install_docker.sh" ;;
            7)  run_script "1panel_manager.sh" ;;
            8)  run_script "xui_manager.sh" ;;
            9)  run_script "easytier_manager.sh" ;;
            10) run_script "hysteria_manager.sh" ;;
            11) run_script "mtproxy.sh" ;;
            12) run_script "disk_mount.sh" ;;
            13) run_script "file_share.sh" ;;
            14) run_script "file_sync.sh" ;;
            15) run_script "download_manager.sh" ;;
            16) run_script "immortalwrt_build.sh" ;;
            a|A) list_all_scripts ;;
            0|q|Q)
                info "再见！"
                exit 0
                ;;
            *)
                warn "无效选项：$choice"
                sleep 1
                ;;
        esac
    done
}

main "$@"
