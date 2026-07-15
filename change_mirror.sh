#!/bin/bash
#=============================================================================
# 换源管理脚本
# 功能：系统软件源 / Docker 镜像源 换源 + 备份 + 恢复
# 支持：Ubuntu / Debian / CentOS Stream / Rocky / AlmaLinux / Fedora / RHEL / OpenWrt
# 用法：chmod +x change_mirror.sh && sudo ./change_mirror.sh
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
BACKUP_DIR="/opt/mirror_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUDO=""

check_root() {
    if [[ $EUID -ne 0 ]]; then
        SUDO="sudo"
    else
        SUDO=""
    fi
}

#-------------------- 获取系统信息 --------------------
get_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID=${ID,,}
        DISTRO_NAME=${PRETTY_NAME}
        DISTRO_VERSION=${VERSION_ID}
        DISTRO_CODENAME=${VERSION_CODENAME}
    else
        error "无法检测系统发行版"
    fi
}

get_codename() {
    # 对于没有 VERSION_CODENAME 的系统，手动推导
    if [[ -n "$DISTRO_CODENAME" ]]; then
        echo "$DISTRO_CODENAME"
        return
    fi

    case "$DISTRO_ID" in
        ubuntu)
            if [[ -n "$DISTRO_VERSION" ]]; then
                case "$DISTRO_VERSION" in
                    24.04|24.10) echo "noble" ;;
                    22.04) echo "jammy" ;;
                    20.04) echo "focal" ;;
                    18.04) echo "bionic" ;;
                esac
            fi
            ;;
        debian)
            if [[ -n "$DISTRO_VERSION" ]]; then
                case "$DISTRO_VERSION" in
                    12|12.*) echo "bookworm" ;;
                    11|11.*) echo "bullseye" ;;
                    10|10.*) echo "buster" ;;
                esac
            fi
            ;;
    esac
}

detect_pkg_manager() {
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            PKG_MGR="apt"
            ;;
        centos|rhel|rocky|almalinux|ol|fedora)
            if command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        openwrt|lede)
            PKG_MGR="opkg"
            ;;
        *)
            error "不支持的发行版: $DISTRO_ID"
            ;;
    esac
}

#-------------------- 主菜单 --------------------
show_menu() {
    clear
    sep
    echo -e "${BOLD}            换源管理脚本（系统源 & Docker 源）${NC}"
    sep
    echo ""
    echo -e "  ${CYAN}【系统软件源】${NC}"
    echo -e "  ${CYAN} 1)${NC} 查看当前软件源"
    echo -e "  ${CYAN} 2)${NC} 更换系统软件源（选择镜像站）"
    echo -e "  ${CYAN} 3)${NC} 测试各镜像站速度，自动选择最快"
    echo -e ""
    echo -e "  ${CYAN}【Docker 镜像源】${NC}"
    echo -e "  ${CYAN} 4)${NC} 查看 Docker 镜像源"
    echo -e "  ${CYAN} 5)${NC} 更换 Docker 镜像源（选择镜像站）"
    echo -e ""
    echo -e "  ${CYAN}【备份 & 恢复】${NC}"
    echo -e "  ${CYAN} 6)${NC} 备份当前所有源配置"
    echo -e "  ${CYAN} 7)${NC} 查看备份列表"
    echo -e "  ${CYAN} 8)${NC} 从备份恢复"
    echo -e "  ${CYAN} 9)${NC} 恢复为官方源"
    echo -e ""
    echo -e "  ${CYAN} 0)${NC} 退出"
    sep
    echo -n "请输入选项: "
}

#-------------------- 功能 1：查看当前源 --------------------
show_current_source() {
    sep
    echo -e "${BOLD}              当前软件源配置${NC}"
    sep
    echo ""

    get_distro
    detect_pkg_manager

    echo -e "  ${BLUE}系统：${NC}${DISTRO_NAME}"
    echo -e "  ${BLUE}包管理器：${NC}${PKG_MGR}"
    echo ""

    if [[ "$PKG_MGR" == "apt" ]]; then
        echo -e "  ${BOLD}主源文件：${NC}"
        if [[ -f /etc/apt/sources.list ]]; then
            echo -e "  ${CYAN}/etc/apt/sources.list${NC}"
            cat -n /etc/apt/sources.list 2>/dev/null | grep -v "^#" | grep -v "^$" | while read -r line; do
                echo -e "    ${line}"
            done
        fi
        echo ""

        echo -e "  ${BOLD}附加源目录：${NC}"
        if [[ -d /etc/apt/sources.list.d ]]; then
            for f in /etc/apt/sources.list.d/*.list; do
                [[ -f "$f" ]] || continue
                echo -e "  ${CYAN}${f}${NC}"
                grep -v "^#" "$f" | grep -v "^$" | head -5 | while read -r line; do
                    echo -e "    ${line}"
                done
                echo ""
            done
        fi
    elif [[ "$PKG_MGR" == "opkg" ]]; then
        show_opkg_current_body
    else
        echo -e "  ${BOLD}YUM/DNF 仓库配置：${NC}"
        for f in /etc/yum.repos.d/*.repo; do
            [[ -f "$f" ]] || continue
            echo -e "  ${CYAN}${f}${NC}"
            grep -E "^\[" "$f" | while read -r line; do
                echo -e "    ${line}"
            done
            echo ""
        done
    fi

    sep
}

#-------------------- 功能 2：更换系统软件源 --------------------
change_system_mirror() {
    sep
    echo -e "${BOLD}              更换系统软件源${NC}"
    sep
    echo ""

    get_distro
    detect_pkg_manager
    local codename=$(get_codename)

    echo -e "  ${BLUE}系统：${NC}${DISTRO_NAME} (代号: ${codename:-未知})"
    echo ""

    # 选择镜像站
    echo -e "  ${BOLD}请选择镜像站：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 阿里云         ${YELLOW}mirrors.aliyun.com${NC}"
    echo -e "  ${CYAN} 2)${NC} 清华大学 TUNA  ${YELLOW}mirrors.tuna.tsinghua.edu.cn${NC}"
    echo -e "  ${CYAN} 3)${NC} 中国科技大学    ${YELLOW}mirrors.ustc.edu.cn${NC}"
    echo -e "  ${CYAN} 4)${NC} 网易 163       ${YELLOW}mirrors.163.com${NC}"
    echo -e "  ${CYAN} 5)${NC} 华为云         ${YELLOW}repo.huaweicloud.com${NC}"
    echo -e "  ${CYAN} 6)${NC} 腾讯云         ${YELLOW}mirrors.cloud.tencent.com${NC}"
    echo -e "  ${CYAN} 7)${NC} 搜狐           ${YELLOW}mirrors.sohu.com${NC}"
    echo ""
    echo -n "请选择 [1-7]（默认 1 阿里云）: "
    read -r mirror_choice

    case "$mirror_choice" in
        1) MIRROR="aliyun" ;;
        2) MIRROR="tuna" ;;
        3) MIRROR="ustc" ;;
        4) MIRROR="163" ;;
        5) MIRROR="huawei" ;;
        6) MIRROR="tencent" ;;
        7) MIRROR="sohu" ;;
        "") MIRROR="aliyun" ;;
        *) warn "无效选项，默认使用阿里云"; MIRROR="aliyun" ;;
    esac

    echo ""

    # 先备份
    backup_sources

    # 根据发行版换源
    case "$PKG_MGR" in
        apt)
            change_apt_mirror "$MIRROR" "$codename"
            ;;
        dnf|yum)
            change_yum_mirror "$MIRROR"
            ;;
        opkg)
            change_opkg_mirror_advanced "$MIRROR"
            ;;
    esac
}

#-------------------- 备份源配置 --------------------
backup_sources() {
    info "备份当前源配置..."

    $SUDO mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"

    if [[ "$PKG_MGR" == "apt" ]]; then
        [[ -f /etc/apt/sources.list ]] && $SUDO cp /etc/apt/sources.list "${BACKUP_DIR}/${TIMESTAMP}/"
        [[ -d /etc/apt/sources.list.d ]] && $SUDO cp -r /etc/apt/sources.list.d "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
    elif [[ "$PKG_MGR" == "opkg" ]]; then
        [[ -f /etc/opkg/distfeeds.conf ]] && $SUDO cp /etc/opkg/distfeeds.conf "${BACKUP_DIR}/${TIMESTAMP}/"
        [[ -f /etc/opkg/customfeeds.conf ]] && $SUDO cp /etc/opkg/customfeeds.conf "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
    else
        [[ -d /etc/yum.repos.d ]] && $SUDO cp -r /etc/yum.repos.d "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
    fi

    # Docker 源
    [[ -f /etc/docker/daemon.json ]] && $SUDO cp /etc/docker/daemon.json "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null

    # Docker 仓库
    [[ -d /etc/apt/sources.list.d ]] && $SUDO cp /etc/apt/sources.list.d/docker.list "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
    [[ -f /etc/yum.repos.d/docker-ce.repo ]] && $SUDO cp /etc/yum.repos.d/docker-ce.repo "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null

    # 记录元信息
    cat > "${BACKUP_DIR}/${TIMESTAMP}/backup_info.txt" <<EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
系统: ${DISTRO_NAME}
包管理器: ${PKG_MGR}
内核: $(uname -r)
EOF

    ok "备份已保存到 ${BACKUP_DIR}/${TIMESTAMP}"
    echo ""
}

#-------------------- apt 换源 --------------------
change_apt_mirror() {
    local mirror=$1
    local codename=$2

    if [[ -z "$codename" ]]; then
        error "无法获取系统代号，请手动换源"
    fi

    local base_url=""
    local mirror_name=""

    case "$mirror" in
        aliyun)
            base_url="mirrors.aliyun.com"
            mirror_name="阿里云"
            ;;
        tuna)
            base_url="mirrors.tuna.tsinghua.edu.cn"
            mirror_name="清华大学 TUNA"
            ;;
        ustc)
            base_url="mirrors.ustc.edu.cn"
            mirror_name="中国科技大学"
            ;;
        163)
            base_url="mirrors.163.com"
            mirror_name="网易 163"
            ;;
        huawei)
            base_url="repo.huaweicloud.com"
            mirror_name="华为云"
            ;;
        tencent)
            base_url="mirrors.cloud.tencent.com"
            mirror_name="腾讯云"
            ;;
        sohu)
            base_url="mirrors.sohu.com"
            mirror_name="搜狐"
            ;;
    esac

    case "$DISTRO_ID" in
        ubuntu)
            info "配置 Ubuntu ${codename} -> ${mirror_name}..."
            $SUDO tee /etc/apt/sources.list > /dev/null <<EOF
# Ubuntu ${codename} ${mirror_name}源
deb https://${base_url}/ubuntu/ ${codename} main restricted universe multiverse
deb https://${base_url}/ubuntu/ ${codename}-updates main restricted universe multiverse
deb https://${base_url}/ubuntu/ ${codename}-security main restricted universe multiverse
deb https://${base_url}/ubuntu/ ${codename}-backports main restricted universe multiverse
EOF
            ;;
        debian)
            info "配置 Debian ${codename} -> ${mirror_name}..."
            $SUDO tee /etc/apt/sources.list > /dev/null <<EOF
# Debian ${codename} ${mirror_name}源
deb https://${base_url}/debian/ ${codename} main contrib non-free non-free-firmware
deb https://${base_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb https://${base_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
deb https://${base_url}/debian/ ${codename}-backports main contrib non-free non-free-firmware
EOF
            ;;
        linuxmint|pop)
            warn "Linux Mint / Pop!_OS 建议保留官方源，仅作为基础换源"
            info "配置基于 ${codename} -> ${mirror_name}..."
            $SUDO tee /etc/apt/sources.list > /dev/null <<EOF
# ${DISTRO_ID} (base: ${codename}) ${mirror_name}源
deb https://${base_url}/ubuntu/ ${codename} main restricted universe multiverse
deb https://${base_url}/ubuntu/ ${codename}-updates main restricted universe multiverse
deb https://${base_url}/ubuntu/ ${codename}-security main restricted universe multiverse
EOF
            ;;
    esac

    ok "系统软件源已更换为 ${mirror_name}"

    # 清理 apt 缓存并更新
    echo ""
    info "更新软件源索引..."
    $SUDO apt-get clean
    $SUDO apt-get update

    echo ""
    echo -e "  ${GREEN}${BOLD}● 系统源更换完成！${NC}"
    echo -e "  ${BLUE}当前源：${NC}${mirror_name} (${base_url})"
    echo -e "  ${BLUE}备份位置：${NC}${BACKUP_DIR}/${TIMESTAMP}"

    sep
}

#-------------------- yum/dnf 换源 --------------------
change_yum_mirror() {
    local mirror=$1

    local base_url=""
    local mirror_name=""

    case "$mirror" in
        aliyun)
            base_url="mirrors.aliyun.com"
            mirror_name="阿里云"
            ;;
        tuna)
            base_url="mirrors.tuna.tsinghua.edu.cn"
            mirror_name="清华大学 TUNA"
            ;;
        ustc)
            base_url="mirrors.ustc.edu.cn"
            mirror_name="中国科技大学"
            ;;
        163)
            base_url="mirrors.163.com"
            mirror_name="网易 163"
            ;;
        huawei)
            base_url="repo.huaweicloud.com"
            mirror_name="华为云"
            ;;
        tencent)
            base_url="mirrors.cloud.tencent.com"
            mirror_name="腾讯云"
            ;;
        sohu)
            base_url="mirrors.sohu.com"
            mirror_name="搜狐"
            ;;
    esac

    local major_version=$(echo "$DISTRO_VERSION" | cut -d. -f1)

    case "$DISTRO_ID" in
        rocky)
            info "配置 Rocky Linux ${major_version} -> ${mirror_name}..."
            $SUDO sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                       -e "s|^#baseurl=https://dl.rockylinux.org/\$contentdir|baseurl=https://${base_url}/rockylinux|g" \
                       -i /etc/yum.repos.d/rocky-*.repo
            ;;
        almalinux)
            info "配置 AlmaLinux ${major_version} -> ${mirror_name}..."
            $SUDO sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                       -e "s|^#baseurl=https://repo.almalinux.org|baseurl=https://${base_url}/almalinux|g" \
                       -i /etc/yum.repos.d/almalinux-*.repo
            ;;
        centos)
            if [[ "$major_version" == "9" ]] || [[ "$major_version" == "8" ]]; then
                info "配置 CentOS Stream ${major_version} -> ${mirror_name}..."
                # CentOS Stream 需要完整替换
                $SUDO rm -f /etc/yum.repos.d/CentOS-*.repo
                $SUDO tee /etc/yum.repos.d/CentOS-Stream-BaseOS.repo > /dev/null <<EOF
[baseos]
name=CentOS Stream ${major_version} - BaseOS - ${mirror_name}
baseurl=https://${base_url}/centos-stream/${major_version}-stream/BaseOS/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF

                $SUDO tee /etc/yum.repos.d/CentOS-Stream-AppStream.repo > /dev/null <<EOF
[appstream]
name=CentOS Stream ${major_version} - AppStream - ${mirror_name}
baseurl=https://${base_url}/centos-stream/${major_version}-stream/AppStream/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF

                $SUDO tee /etc/yum.repos.d/CentOS-Stream-Extras.repo > /dev/null <<EOF
[extras-common]
name=CentOS Stream ${major_version} - Extras - ${mirror_name}
baseurl=https://${base_url}/centos-stream/${major_version}-stream/Extras/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF
            else
                warn "CentOS ${major_version} 不支持自动换源，请手动配置"
                return
            fi
            ;;
        fedora)
            info "配置 Fedora ${major_version} -> ${mirror_name}..."
            $SUDO sed -e "s|^metalink=|#metalink=|g" \
                       -e "s|^#baseurl=https://download.example/pub/fedora/linux|baseurl=https://${base_url}/fedora|g" \
                       -i /etc/yum.repos.d/fedora-*.repo
            ;;
        *)
            warn "当前发行版 (${DISTRO_ID}) 换源需要手动配置"
            echo -e "  ${CYAN}请参考：${NC}https://developer.aliyun.com/mirror/"
            return
            ;;
    esac

    ok "系统软件源已更换为 ${mirror_name}"

    echo ""
    info "更新软件源索引..."
    if command -v dnf &>/dev/null; then
        $SUDO dnf clean all
        $SUDO dnf makecache
    else
        $SUDO yum clean all
        $SUDO yum makecache
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}● 系统源更换完成！${NC}"
    echo -e "  ${BLUE}当前源：${NC}${mirror_name} (${base_url})"
    echo -e "  ${BLUE}备份位置：${NC}${BACKUP_DIR}/${TIMESTAMP}"

    sep
}

#-------------------- OpenWrt 信息获取 --------------------
get_openwrt_info() {
    OPENWRT_VERSION=""
    OPENWRT_ARCH=""
    OPENWRT_TARGET=""

    if [[ -f /etc/openwrt_release ]]; then
        . /etc/openwrt_release 2>/dev/null
        OPENWRT_VERSION="${DISTRIB_RELEASE}"
        OPENWRT_ARCH="${DISTRIB_ARCH}"
        OPENWRT_TARGET="${DISTRIB_TARGET}"
    fi

    if [[ -z "$OPENWRT_VERSION" && -f /etc/os-release ]]; then
        . /etc/os-release 2>/dev/null
        OPENWRT_VERSION="${VERSION_ID}"
    fi
}

#-------------------- 显示 OpenWrt 当前源（主体内容）--------------------
show_opkg_current_body() {
    get_openwrt_info

    echo -e "  ${BLUE}版本：${NC}${OPENWRT_VERSION:-未知}"
    echo -e "  ${BLUE}架构：${NC}${OPENWRT_ARCH:-未知}"
    echo -e "  ${BLUE}目标：${NC}${OPENWRT_TARGET:-未知}"
    echo ""

    if [[ -f /etc/opkg/distfeeds.conf ]]; then
        echo -e "  ${BOLD}/etc/opkg/distfeeds.conf 内容：${NC}"
        while IFS= read -r line; do
            echo -e "    ${CYAN}${line}${NC}"
        done < /etc/opkg/distfeeds.conf
    else
        warn "未找到 /etc/opkg/distfeeds.conf"
    fi

    if [[ -f /etc/opkg/customfeeds.conf ]]; then
        echo ""
        echo -e "  ${BOLD}/etc/opkg/customfeeds.conf 内容：${NC}"
        while IFS= read -r line; do
            echo -e "    ${CYAN}${line}${NC}"
        done < /etc/opkg/customfeeds.conf
    fi
}

#-------------------- OpenWrt 换源（高级模式）--------------------
change_opkg_mirror_advanced() {
    local mirror=$1

    local base_url=""
    local mirror_name=""

    case "$mirror" in
        aliyun)
            base_url="mirrors.aliyun.com/openwrt"
            mirror_name="阿里云"
            ;;
        tuna)
            base_url="mirrors.tuna.tsinghua.edu.cn/openwrt"
            mirror_name="清华大学 TUNA"
            ;;
        ustc)
            base_url="mirrors.ustc.edu.cn/openwrt"
            mirror_name="中国科技大学"
            ;;
        163)
            base_url="mirrors.163.com/openwrt"
            mirror_name="网易 163"
            ;;
        huawei)
            base_url="repo.huaweicloud.com/openwrt"
            mirror_name="华为云"
            ;;
        tencent)
            base_url="mirrors.cloud.tencent.com/openwrt"
            mirror_name="腾讯云"
            ;;
        sohu)
            base_url="mirrors.sohu.com/openwrt"
            mirror_name="搜狐"
            ;;
    esac

    get_openwrt_info

    echo ""
    echo -e "  ${BLUE}检测到版本：${NC}${OPENWRT_VERSION:-未知}"
    echo -e "  ${BLUE}检测到架构：${NC}${OPENWRT_ARCH:-未知}"
    echo ""

    echo -e "  ${BOLD}请选择换源模式：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 智能替换（推荐）"
    echo -e "     只替换镜像域名，保留当前版本和架构路径"
    echo -e "     ${GREEN}适用于同一版本内切换镜像站，最安全${NC}"
    echo ""
    echo -e "  ${CYAN} 2)${NC} 重新生成完整源配置"
    echo -e "     根据版本和架构重新生成所有 feed 源"
    echo -e "     ${YELLOW}适用于版本不匹配、源损坏或换版本的情况${NC}"
    echo ""
    echo -n "  请选择 [1-2]（默认 1）: "
    read -r mode_choice

    case "$mode_choice" in
        2)
            echo ""
            echo -n "  输入 OpenWrt 版本号（如 23.05.3, SNAPSHOT, 留空使用当前 ${OPENWRT_VERSION:-未知}）: "
            read -r input_version
            local target_version="${input_version:-$OPENWRT_VERSION}"

            if [[ -z "$target_version" ]]; then
                error "无法获取版本号，请手动输入"
                return 1
            fi

            echo -n "  输入架构名称（如 x86_64, aarch64_cortex-a53, 留空使用当前 ${OPENWRT_ARCH:-未知}）: "
            read -r input_arch
            local target_arch="${input_arch:-$OPENWRT_ARCH}"

            if [[ -z "$target_arch" ]]; then
                error "无法获取架构名称，请手动输入"
                return 1
            fi

            # 生成完整源配置
            local url_prefix="https://${base_url}"
            local pkg_url=""

            if [[ "$target_version" == "SNAPSHOT" ]] || [[ "$target_version" == "snapshot" ]]; then
                pkg_url="${url_prefix}/snapshots/packages/${target_arch}"
            else
                pkg_url="${url_prefix}/releases/${target_version}/packages/${target_arch}"
            fi

            info "生成完整源配置..."
            $SUDO tee /etc/opkg/distfeeds.conf > /dev/null <<EOF
src/gz openwrt_base ${pkg_url}/base
src/gz openwrt_luci ${pkg_url}/luci
src/gz openwrt_packages ${pkg_url}/packages
src/gz openwrt_routing ${pkg_url}/routing
src/gz openwrt_telephony ${pkg_url}/telephony
EOF
            ok "已重新生成 /etc/opkg/distfeeds.conf"
            ;;
        *)
            # 智能替换模式
            info "执行智能替换（只更换镜像域名）..."
            $SUDO sed -i "s|downloads.openwrt.org|${base_url}|g" /etc/opkg/distfeeds.conf
            ok "已替换为 ${mirror_name}"
            ;;
    esac

    # 检查是否需要 HTTPS 支持
    if grep -q "^src/gz.*https://" /etc/opkg/distfeeds.conf 2>/dev/null; then
        if ! opkg list-installed 2>/dev/null | grep -q "libustream"; then
            warn "当前源使用 HTTPS，但可能缺少 HTTPS 支持包"
            echo -e "  ${YELLOW}如遇 opkg update 失败，请尝试：${NC}"
            echo -e "  ${CYAN}opkg install libustream-mbedtls${NC}"
            echo -e "  ${CYAN}或将源中的 https 改为 http${NC}"
        fi
    fi

    echo ""
    info "更新 opkg 软件源索引..."
    if opkg update; then
        ok "opkg 更新成功"
    else
        warn "opkg 更新失败"
        echo -e "  ${YELLOW}可能的解决方案：${NC}"
        echo -e "  1. 检查网络连接"
        echo -e "  2. 确认镜像站支持该版本/架构"
        echo -e "  3. 尝试安装 HTTPS 支持：opkg install libustream-mbedtls"
        echo -e "  4. 尝试将 https 改为 http"
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}● OpenWrt 源更换完成！${NC}"
    echo -e "  ${BLUE}当前源：${NC}${mirror_name}"
    echo -e "  ${BLUE}备份位置：${NC}${BACKUP_DIR}/${TIMESTAMP}"

    sep
}

#-------------------- 功能 3：自动测速选最快源 --------------------
auto_select_mirror() {
    sep
    echo -e "${BOLD}              自动测速选择最快镜像站${NC}"
    sep
    echo ""

    get_distro
    detect_pkg_manager
    local codename=$(get_codename)

    local mirrors=(
        "mirrors.aliyun.com:阿里云"
        "mirrors.tuna.tsinghua.edu.cn:清华大学"
        "mirrors.ustc.edu.cn:中科大"
        "mirrors.163.com:网易"
        "mirrors.cloud.tencent.com:腾讯云"
        "repo.huaweicloud.com:华为云"
    )

    echo -e "  ${YELLOW}正在测试各镜像站响应速度...${NC}"
    echo ""

    local best_mirror=""
    local best_time=99999
    local best_name=""

    for mirror in "${mirrors[@]}"; do
        local url="${mirror%%:*}"
        local name="${mirror##*:}"
        echo -n "  测试 ${name} ... "

        local start_time=$(date +%s%N)
        if curl -s --max-time 5 -o /dev/null -w "%{http_code}" "https://${url}/" | grep -q "200\|301\|302"; then
            local end_time=$(date +%s%N)
            local elapsed=$(( (end_time - start_time) / 1000000 ))
            if [[ "$elapsed" -lt "$best_time" ]]; then
                best_time=$elapsed
                best_mirror="$url"
                best_name="$name"
            fi
            echo -e "${GREEN}${elapsed}ms ✓${NC}"
        else
            echo -e "${RED}超时/不可用 ✗${NC}"
        fi
    done

    echo ""
    if [[ -z "$best_mirror" ]]; then
        error "所有镜像站均不可用，请检查网络"
    fi

    echo -e "  ${GREEN}${BOLD}最快镜像站：${best_name} (${best_mirror}) ${best_time}ms${NC}"
    echo ""

    echo -n "  是否更换为此镜像站？(Y/n): "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    # 映射到内部名称
    local mirror_id=""
    case "$best_mirror" in
        *aliyun*)     mirror_id="aliyun" ;;
        *tuna*)       mirror_id="tuna" ;;
        *ustc*)       mirror_id="ustc" ;;
        *163*)        mirror_id="163" ;;
        *tencent*)    mirror_id="tencent" ;;
        *huawei*)     mirror_id="huawei" ;;
    esac

    echo ""
    if [[ -n "$mirror_id" ]]; then
        backup_sources
        case "$PKG_MGR" in
            apt)  change_apt_mirror "$mirror_id" "$codename" ;;
            dnf|yum) change_yum_mirror "$mirror_id" ;;
            opkg) change_opkg_mirror_advanced "$mirror_id" ;;
        esac
    fi
}

#-------------------- 功能 4：查看 Docker 源 --------------------
show_docker_source() {
    sep
    echo -e "${BOLD}              当前 Docker 镜像源${NC}"
    sep
    echo ""

    if [[ -f /etc/docker/daemon.json ]]; then
        echo -e "  ${BOLD}/etc/docker/daemon.json 内容：${NC}"
        cat /etc/docker/daemon.json 2>/dev/null | while read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done
        echo ""

        echo -e "  ${BOLD}生效的镜像加速源：${NC}"
        if docker info 2>/dev/null | grep -q "Registry Mirrors"; then
            docker info 2>/dev/null | grep -A 10 "Registry Mirrors" | while read -r line; do
                echo -e "  ${CYAN}${line}${NC}"
            done
        else
            warn "未检测到生效的镜像加速源"
        fi
    else
        warn "Docker 配置文件不存在: /etc/docker/daemon.json"
        echo -e "  ${YELLOW}当前使用 Docker Hub 官方源（无加速）${NC}"
    fi

    # Docker 仓库源
    echo ""
    echo -e "  ${BOLD}Docker CE 安装源：${NC}"
    if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
        echo -e "  ${CYAN}/etc/apt/sources.list.d/docker.list${NC}"
        grep -v "^#" /etc/apt/sources.list.d/docker.list | grep -v "^$" | while read -r line; do
            echo -e "    ${line}"
        done
    elif [[ -f /etc/yum.repos.d/docker-ce.repo ]]; then
        echo -e "  ${CYAN}/etc/yum.repos.d/docker-ce.repo${NC}"
        grep -E "^\[|baseurl" /etc/yum.repos.d/docker-ce.repo | while read -r line; do
            echo -e "    ${line}"
        done
    else
        warn "未检测到 Docker CE 安装源配置"
    fi

    sep
}

#-------------------- 功能 5：更换 Docker 源 --------------------
change_docker_mirror() {
    sep
    echo -e "${BOLD}              更换 Docker 镜像源${NC}"
    sep
    echo ""

    echo -e "  ${BOLD}选择镜像加速源：${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} 综合推荐（多源，最稳定）"
    echo -e "  ${CYAN} 2)${NC} 阿里云          ${YELLOW}docker.1ms.run${NC}"
    echo -e "  ${CYAN} 3)${NC} DaoCloud        ${YELLOW}docker.m.daocloud.io${NC}"
    echo -e "  ${CYAN} 4)${NC} Xuanyuan        ${YELLOW}docker.xuanyuan.me${NC}"
    echo -e "  ${CYAN} 5)${NC} 恢复为官方源（清除加速）"
    echo ""
    echo -n "请选择 [1-5]（默认 1）: "
    read -r docker_choice

    echo ""

    # 备份
    if [[ -f /etc/docker/daemon.json ]]; then
        $SUDO mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"
        $SUDO cp /etc/docker/daemon.json "${BACKUP_DIR}/${TIMESTAMP}/daemon.json"
        ok "Docker 配置已备份"
    fi

    $SUDO mkdir -p /etc/docker

    local mirrors_json=""
    local mirror_desc=""

    case "$docker_choice" in
        1)
            mirrors_json='    "https://docker.1ms.run",\n    "https://docker.m.daocloud.io",\n    "https://docker.xuanyuan.me"'
            mirror_desc="综合推荐（docker.1ms.run + DaoCloud + Xuanyuan）"
            ;;
        2)
            mirrors_json='    "https://docker.1ms.run"'
            mirror_desc="阿里云（docker.1ms.run）"
            ;;
        3)
            mirrors_json='    "https://docker.m.daocloud.io"'
            mirror_desc="DaoCloud"
            ;;
        4)
            mirrors_json='    "https://docker.xuanyuan.me"'
            mirror_desc="Xuanyuan"
            ;;
        5)
            # 恢复官方源 - 只保留基础配置
            info "恢复 Docker 为官方源（清除镜像加速）..."
            $SUDO tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
    "features": {
        "buildkit": true
    }
}
EOF
            $SUDO systemctl daemon-reload
            $SUDO systemctl restart docker 2>/dev/null || warn "Docker 服务未运行，跳过重启"
            echo ""
            echo -e "  ${GREEN}${BOLD}● Docker 已恢复为官方源${NC}"
            sep
            return
            ;;
        "")
            mirrors_json='    "https://docker.1ms.run",\n    "https://docker.m.daocloud.io",\n    "https://docker.xuanyuan.me"'
            mirror_desc="综合推荐（docker.1ms.run + DaoCloud + Xuanyuan）"
            ;;
        *)
            warn "无效选项，使用综合推荐"
            mirrors_json='    "https://docker.1ms.run",\n    "https://docker.m.daocloud.io",\n    "https://docker.xuanyuan.me"'
            mirror_desc="综合推荐"
            ;;
    esac

    # 保留原有的非 mirrors 配置
    local extra_config=""
    if [[ -f /etc/docker/daemon.json ]]; then
        extra_config=$(grep -v "registry-mirrors" /etc/docker/daemon.json 2>/dev/null | grep -v "^{" | grep -v "^}" | grep -v "^\s*$" | head -20)
    fi

    info "写入 Docker 镜像加速配置..."
    echo -e -n "{
    \"registry-mirrors\": [\n${mirrors_json}\n    ]" > /tmp/daemon.json.tmp

    if [[ -n "$extra_config" ]]; then
        echo -e ",\n${extra_config}" >> /tmp/daemon.json.tmp
    fi

    echo -e "\n}" >> /tmp/daemon.json.tmp
    $SUDO mv /tmp/daemon.json.tmp /etc/docker/daemon.json

    ok "镜像加速源：${mirror_desc}"

    # 重启 Docker
    echo ""
    info "重启 Docker 服务..."
    $SUDO systemctl daemon-reload
    $SUDO systemctl restart docker 2>/dev/null || warn "Docker 服务未运行，跳过重启"

    echo ""
    echo -e "  ${GREEN}${BOLD}● Docker 镜像源更换完成！${NC}"
    echo -e "  ${BLUE}当前加速源：${NC}${mirror_desc}"
    echo -e "  ${BLUE}备份位置：${NC}${BACKUP_DIR}/${TIMESTAMP}"

    sep
}

#-------------------- 功能 6：备份所有源 --------------------
backup_all() {
    sep
    echo -e "${BOLD}              备份所有源配置${NC}"
    sep
    echo ""

    get_distro
    detect_pkg_manager

    $SUDO mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"

    info "开始备份..."

    # 系统 apt 源
    if [[ -f /etc/apt/sources.list ]]; then
        $SUDO cp /etc/apt/sources.list "${BACKUP_DIR}/${TIMESTAMP}/"
        ok "已备份 /etc/apt/sources.list"
    fi
    if [[ -d /etc/apt/sources.list.d ]]; then
        $SUDO cp -r /etc/apt/sources.list.d "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
        ok "已备份 /etc/apt/sources.list.d/"
    fi

    # 系统 yum/dnf 源
    if [[ -d /etc/yum.repos.d ]]; then
        $SUDO cp -r /etc/yum.repos.d "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
        ok "已备份 /etc/yum.repos.d/"
    fi

    # Docker 配置
    if [[ -f /etc/docker/daemon.json ]]; then
        $SUDO cp /etc/docker/daemon.json "${BACKUP_DIR}/${TIMESTAMP}/"
        ok "已备份 /etc/docker/daemon.json"
    fi

    # pip 配置
    if [[ -f /etc/pip.conf ]]; then
        $SUDO cp /etc/pip.conf "${BACKUP_DIR}/${TIMESTAMP}/" 2>/dev/null
        ok "已备份 /etc/pip.conf"
    fi
    if [[ -f ~/.pip/pip.conf ]]; then
        cp ~/.pip/pip.conf "${BACKUP_DIR}/${TIMESTAMP}/pip.conf.user" 2>/dev/null
        ok "已备份 ~/.pip/pip.conf"
    fi

    # npm 配置
    if [[ -f ~/.npmrc ]]; then
        cp ~/.npmrc "${BACKUP_DIR}/${TIMESTAMP}/npmrc.user" 2>/dev/null
        ok "已备份 ~/.npmrc"
    fi

    # 记录元信息
    cat > "${BACKUP_DIR}/${TIMESTAMP}/backup_info.txt" <<EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
系统: ${DISTRO_NAME}
包管理器: ${PKG_MGR}
内核: $(uname -r)
主机名: $(hostname)
IP: $(hostname -I 2>/dev/null | awk '{print $1}')
EOF

    echo ""
    echo -e "  ${GREEN}${BOLD}● 备份完成！${NC}"
    echo -e "  ${BLUE}备份位置：${NC}${BACKUP_DIR}/${TIMESTAMP}/"
    echo -e "  ${BLUE}备份内容：${NC}"
    $SUDO ls -la "${BACKUP_DIR}/${TIMESTAMP}/" | tail -n +2 | while read -r line; do
        echo -e "    ${CYAN}${line}${NC}"
    done

    sep
}

#-------------------- 功能 7：查看备份列表 --------------------
list_backups() {
    sep
    echo -e "${BOLD}              备份列表${NC}"
    sep
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "暂无备份"
        sep
        return
    fi

    local idx=1
    declare -A backup_map

    for dir in $(ls -dt "${BACKUP_DIR}"/*/ 2>/dev/null); do
        [[ -d "$dir" ]] || continue
        local dirname=$(basename "$dir")
        local info_file="${dir}backup_info.txt"

        local meta=""
        if [[ -f "$info_file" ]]; then
            meta=$(grep "系统" "$info_file" | cut -d: -f2- | xargs)
        fi

        local file_count=$(find "$dir" -maxdepth 2 -type f ! -name "backup_info.txt" | wc -l)

        echo -e "  ${CYAN}[$idx]${NC} ${BOLD}${dirname}${NC}"
        echo -e "       ${meta:-未知系统}"
        echo -e "       文件数: ${file_count}"
        echo ""

        backup_map[$idx]="$dir"
        idx=$((idx + 1))
    done

    echo ""
    echo -n "  输入备份编号查看详情（或 Enter 返回）: "
    read -r view_idx

    if [[ -n "$view_idx" && -n "${backup_map[$view_idx]}" ]]; then
        local target="${backup_map[$view_idx]}"
        echo ""
        echo -e "  ${BOLD}备份详情：${CYAN}${target}${NC}"
        echo ""
        find "$target" -type f | while read -r f; do
            echo -e "  ${CYAN}${f}${NC}"
        done
        echo ""

        if [[ -f "${target}/backup_info.txt" ]]; then
            echo -e "  ${BOLD}备份信息：${NC}"
            cat "${target}/backup_info.txt" | while read -r line; do
                echo -e "  ${CYAN}${line}${NC}"
            done
        fi
    fi

    sep
}

#-------------------- 功能 8：从备份恢复 --------------------
restore_backup() {
    sep
    echo -e "${BOLD}              从备份恢复${NC}"
    sep
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "暂无备份，无法恢复"
        sep
        return
    fi

    echo -e "  ${YELLOW}可用备份：${NC}"
    echo ""

    local idx=1
    declare -A backup_map

    for dir in $(ls -dt "${BACKUP_DIR}"/*/ 2>/dev/null); do
        [[ -d "$dir" ]] || continue
        local dirname=$(basename "$dir")
        local info_file="${dir}backup_info.txt"
        local meta=""
        if [[ -f "$info_file" ]]; then
            meta=$(grep "系统" "$info_file" | cut -d: -f2- | xargs)
            meta="${meta} ($(grep '备份时间' "$info_file" | cut -d: -f2- | xargs))"
        fi

        echo -e "  ${CYAN}[$idx]${NC} ${dirname} ${meta:-}"
        backup_map[$idx]="$dir"
        idx=$((idx + 1))
    done

    echo ""
    echo -n "  输入要恢复的备份编号: "
    read -r restore_idx

    if [[ -z "$restore_idx" || -z "${backup_map[$restore_idx]}" ]]; then
        warn "无效选择"
        return
    fi

    local source="${backup_map[$restore_idx]}"
    echo ""
    warn "恢复将覆盖当前所有源配置！"
    echo -e "  ${RED}此操作不可撤销！${NC}"
    echo ""
    echo -n "  确认恢复？请输入 'YES' 确认: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "开始恢复..."

    # 先备份当前配置
    local current_ts=$(date +%Y%m%d_%H%M%S)
    $SUDO mkdir -p "${BACKUP_DIR}/${current_ts}_pre_restore"

    # apt 源
    [[ -f /etc/apt/sources.list ]] && $SUDO cp /etc/apt/sources.list "${BACKUP_DIR}/${current_ts}_pre_restore/"
    [[ -d /etc/apt/sources.list.d ]] && $SUDO cp -r /etc/apt/sources.list.d "${BACKUP_DIR}/${current_ts}_pre_restore/" 2>/dev/null

    # yum/dnf 源
    [[ -d /etc/yum.repos.d ]] && $SUDO cp -r /etc/yum.repos.d "${BACKUP_DIR}/${current_ts}_pre_restore/" 2>/dev/null

    # Docker
    [[ -f /etc/docker/daemon.json ]] && $SUDO cp /etc/docker/daemon.json "${BACKUP_DIR}/${current_ts}_pre_restore/"

    ok "当前配置已自动备份到 ${BACKUP_DIR}/${current_ts}_pre_restore/"

    echo ""

    # 恢复 apt 源
    if [[ -f "${source}/sources.list" ]]; then
        $SUDO cp "${source}/sources.list" /etc/apt/sources.list
        ok "已恢复 /etc/apt/sources.list"
    fi
    if [[ -d "${source}/sources.list.d" ]]; then
        $SUDO rm -rf /etc/apt/sources.list.d/*
        $SUDO cp -r "${source}/sources.list.d/"* /etc/apt/sources.list.d/ 2>/dev/null
        ok "已恢复 /etc/apt/sources.list.d/"
    fi

    # 恢复 yum/dnf 源
    if [[ -d "${source}/yum.repos.d" ]]; then
        $SUDO rm -rf /etc/yum.repos.d/*.repo.bak 2>/dev/null
        $SUDO cp -r "${source}/yum.repos.d/"* /etc/yum.repos.d/ 2>/dev/null
        ok "已恢复 /etc/yum.repos.d/"
    fi

    # 恢复 opkg 源
    if [[ -f "${source}/distfeeds.conf" ]]; then
        $SUDO cp "${source}/distfeeds.conf" /etc/opkg/distfeeds.conf
        ok "已恢复 /etc/opkg/distfeeds.conf"
    fi
    if [[ -f "${source}/customfeeds.conf" ]]; then
        $SUDO cp "${source}/customfeeds.conf" /etc/opkg/customfeeds.conf
        ok "已恢复 /etc/opkg/customfeeds.conf"
    fi

    # 恢复 Docker
    if [[ -f "${source}/daemon.json" ]]; then
        $SUDO cp "${source}/daemon.json" /etc/docker/daemon.json
        ok "已恢复 /etc/docker/daemon.json"
        $SUDO systemctl daemon-reload
        $SUDO systemctl restart docker 2>/dev/null
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}● 恢复完成！${NC}"
    echo -e "  ${BLUE}恢复来源：${NC}${source}"
    echo -e "  ${BLUE}当前备份：${NC}${BACKUP_DIR}/${current_ts}_pre_restore/"

    sep
}

#-------------------- 功能 9：恢复官方源 --------------------
restore_official() {
    sep
    echo -e "${BOLD}              恢复为官方源${NC}"
    sep
    echo ""

    get_distro
    detect_pkg_manager
    local codename=$(get_codename)

    warn "恢复为官方源可能在国内网络较慢"
    echo -n "  确认恢复？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消"
        return
    fi

    echo ""
    info "备份当前配置..."
    backup_sources

    echo ""

    case "$PKG_MGR" in
        apt)
            case "$DISTRO_ID" in
                ubuntu)
                    info "恢复 Ubuntu ${codename} 官方源..."
                    $SUDO tee /etc/apt/sources.list > /dev/null <<EOF
# Ubuntu ${codename} 官方源
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-backports main restricted universe multiverse
EOF
                    ;;
                debian)
                    info "恢复 Debian ${codename} 官方源..."
                    $SUDO tee /etc/apt/sources.list > /dev/null <<EOF
# Debian ${codename} 官方源
deb http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-backports main contrib non-free non-free-firmware
EOF
                    ;;
                *)
                    warn "无法自动恢复此发行版的官方源"
                    return
                    ;;
            esac

            # 清理附加源中的镜像
            if [[ -d /etc/apt/sources.list.d ]]; then
                for f in /etc/apt/sources.list.d/*.list; do
                    [[ -f "$f" ]] || continue
                    if grep -q "mirrors\." "$f" 2>/dev/null; then
                        $SUDO rm -f "$f"
                        ok "移除附加源: $(basename $f)"
                    fi
                done
            fi

            $SUDO apt-get clean
            $SUDO apt-get update
            ;;
        dnf|yum)
            case "$DISTRO_ID" in
                rocky)
                    info "恢复 Rocky Linux 官方源..."
                    $SUDO sed -e 's|^#mirrorlist=|mirrorlist=|g' \
                               -e 's|^baseurl=.*|#baseurl=|g' \
                               -i /etc/yum.repos.d/rocky-*.repo
                    ;;
                almalinux)
                    info "恢复 AlmaLinux 官方源..."
                    $SUDO sed -e 's|^#mirrorlist=|mirrorlist=|g' \
                               -e 's|^baseurl=.*|#baseurl=|g' \
                               -i /etc/yum.repos.d/almalinux-*.repo
                    ;;
                *)
                    warn "无法自动恢复此发行版的官方源"
                    return
                    ;;
            esac

            if command -v dnf &>/dev/null; then
                $SUDO dnf clean all
                $SUDO dnf makecache
            else
                $SUDO yum clean all
                $SUDO yum makecache
            fi
            ;;
        opkg)
            info "恢复 OpenWrt 官方源..."
            if [[ -f /etc/opkg/distfeeds.conf ]]; then
                $SUDO sed -i 's|mirrors\.[^/]*/openwrt|downloads.openwrt.org|g' /etc/opkg/distfeeds.conf
                ok "已恢复 OpenWrt 官方源"
                echo ""
                info "更新 opkg 索引..."
                opkg update
            else
                warn "未找到 /etc/opkg/distfeeds.conf"
            fi
            ;;
    esac

    echo ""
    echo -e "  ${GREEN}${BOLD}● 已恢复为官方源！${NC}"

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
            1) show_current_source ;;
            2) change_system_mirror ;;
            3) auto_select_mirror ;;
            4) show_docker_source ;;
            5) change_docker_mirror ;;
            6) backup_all ;;
            7) list_backups ;;
            8) restore_backup ;;
            9) restore_official ;;
            0|q|Q)
                echo ""
                info "退出换源管理脚本"
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
