#!/bin/bash
#=============================================================================
# Docker 一键安装脚本
# 功能：自动检测系统 -> 选择国内/国外源 -> 安装 Docker CE
# 支持：Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora / RHEL
# 用法：chmod +x install_docker.sh && sudo ./install_docker.sh
#=============================================================================

set -e

#-------------------- 颜色定义 --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#-------------------- 辅助函数 --------------------
info()    { echo -e "${GREEN}[信息]${NC} $*"; }
warn()    { echo -e "${YELLOW}[警告]${NC} $*"; }
error()   { echo -e "${RED}[错误]${NC} $*"; exit 1; }
separator(){ echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

#-------------------- 系统检测 --------------------
detect_os() {
    separator
    echo -e "${BOLD}         Docker 一键安装脚本${NC}"
    echo -e "${BOLD}         自动检测系统环境中...${NC}"
    separator

    # 检查是否为 root
    if [[ $EUID -ne 0 ]]; then
        warn "建议使用 root 用户运行此脚本（当前用户：$(whoami））"
        echo -e "${YELLOW}部分操作需要 sudo 权限，脚本将自动使用 sudo${NC}"
        SUDO="sudo"
    else
        SUDO=""
    fi

    # 检查是否为 Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        error "此脚本仅支持 Linux 系统，当前系统：$(uname -s)"
    fi

    # 检测发行版
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID=${ID,,}
        DISTRO_NAME=${PRETTY_NAME}
        DISTRO_VERSION=${VERSION_ID}
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO_ID="rhel"
        DISTRO_NAME=$(cat /etc/redhat-release)
        DISTRO_VERSION=$(rpm -q --queryformat '%{VERSION}' redhat-release 2>/dev/null || echo "unknown")
    else
        error "无法检测系统发行版，请手动安装 Docker"
    fi

    echo ""
    info "检测到系统信息："
    echo -e "  ${BLUE}发行版：${NC}${DISTRO_NAME}"
    echo -e "  ${BLUE}版本号：${NC}${DISTRO_VERSION}"
    echo -e "  ${BLUE}内  核：${NC}$(uname -r)"
    echo -e "  ${BLUE}架  构：${NC}$(uname -m)"

    # 检查架构
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]] && [[ "$ARCH" != "aarch64" ]]; then
        warn "当前架构 $ARCH 可能不被 Docker 官方支持，将继续尝试安装"
    fi

    # 映射到支持的发行版
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            PKG_MANAGER="apt"
            DISTRO_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux|ol|fedora)
            PKG_MANAGER="yum"
            DISTRO_FAMILY="rhel"
            # 区分 yum 和 dnf
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            fi
            ;;
        *)
            warn "未明确识别的发行版：$DISTRO_ID ($DISTRO_NAME)"
            echo -n "  是否仍尝试基于 Debian/Ubuntu 的 apt 方式安装？(y/N): "
            read -r try_apt
            if [[ "$try_apt" =~ ^[Yy]$ ]]; then
                PKG_MANAGER="apt"
                DISTRO_FAMILY="debian"
            else
                error "不支持的发行版，安装终止"
            fi
            ;;
    esac

    echo -e "  ${BLUE}包管理：${NC}${PKG_MANAGER}"
    echo ""
}

#-------------------- 国内/国外选择 --------------------
choose_region() {
    separator
    echo -e "${BOLD}请选择镜像源区域：${NC}"
    echo -e "  ${CYAN}1)${NC} 国内（使用国内加速镜像，下载更快）"
    echo -e "  ${CYAN}2)${NC} 国外（使用 Docker 官方源）"
    separator
    echo -n "请输入选项 [1/2]（默认 1）: "
    read -r region_choice
    case "$region_choice" in
        2) 
            REGION="overseas"
            info "已选择：国外（Docker 官方源）"
            ;;
        1|"")
            REGION="china"
            info "已选择：国内（加速镜像）"
            ;;
        *)
            warn "无效输入，默认使用国内加速镜像"
            REGION="china"
            ;;
    esac
    echo ""
}

#-------------------- 卸载旧版本 --------------------
remove_old_docker() {
    info "检查并清理旧版本 Docker..."
    
    local old_packages=""
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        old_packages="docker docker-engine docker.io containerd runc"
        for pkg in $old_packages; do
            if $SUDO dpkg -l "$pkg" &>/dev/null 2>&1; then
                info "移除旧包：$pkg"
            fi
        done
        $SUDO apt-get remove -y $old_packages 2>/dev/null || true
    else
        old_packages="docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine"
        for pkg in $old_packages; do
            if $SUDO rpm -q "$pkg" &>/dev/null 2>&1; then
                info "移除旧包：$pkg"
            fi
        done
        $SUDO $PKG_MANAGER remove -y $old_packages 2>/dev/null || true
    fi

    info "旧版本清理完成"
}

#-------------------- 安装依赖 --------------------
install_dependencies() {
    info "安装必要依赖..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        $SUDO apt-get update
        $SUDO apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        $SUDO dnf install -y dnf-utils curl gnupg2
    else
        $SUDO yum install -y yum-utils curl gnupg2
    fi

    info "依赖安装完成"
}

#-------------------- 配置 Docker 仓库源 --------------------
setup_repo() {
    info "配置 Docker 软件源..."

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # Debian 系
        # 识别仓库 URL
        local repo_url
        if [[ "$REGION" == "china" ]]; then
            # 国内使用阿里云的 Docker CE 源
            case "$DISTRO_ID" in
                ubuntu)
                    repo_url="https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
                    ;;
                debian)
                    repo_url="https://mirrors.aliyun.com/docker-ce/linux/debian"
                    ;;
                *)
                    repo_url="https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
                    ;;
            esac
        else
            case "$DISTRO_ID" in
                ubuntu)
                    repo_url="https://download.docker.com/linux/ubuntu"
                    ;;
                debian)
                    repo_url="https://download.docker.com/linux/debian"
                    ;;
                *)
                    repo_url="https://download.docker.com/linux/ubuntu"
                    ;;
            esac
        fi

        # 添加 GPG Key
        local gpg_key_url
        if [[ "$REGION" == "china" ]]; then
            gpg_key_url="https://mirrors.aliyun.com/docker-ce/linux/${DISTRO_ID}/gpg"
        else
            gpg_key_url="https://download.docker.com/linux/${DISTRO_ID}/gpg"
        fi
        
        # 移除旧的 key
        $SUDO rm -f /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
        $SUDO rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        
        # 添加新的 GPG key
        curl -fsSL "$gpg_key_url" | $SUDO gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # 添加仓库
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $repo_url $(lsb_release -cs) stable" | \
            $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

        $SUDO apt-get update
        
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        # dnf (Fedora, Rocky 9+, AlmaLinux 9+, RHEL 9+)
        local repo_url
        if [[ "$REGION" == "china" ]]; then
            repo_url="https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
        else
            repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
        fi
        $SUDO dnf config-manager --add-repo "$repo_url"
        
        # 国内替换为阿里云地址
        if [[ "$REGION" == "china" ]]; then
            $SUDO sed -i 's|download.docker.com|mirrors.aliyun.com/docker-ce|g' /etc/yum.repos.d/docker-ce.repo
        fi

    else
        # yum (CentOS 7, RHEL 7)
        local repo_url
        if [[ "$REGION" == "china" ]]; then
            repo_url="https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
        else
            repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
        fi
        $SUDO yum-config-manager --add-repo "$repo_url"
        
        if [[ "$REGION" == "china" ]]; then
            $SUDO sed -i 's|download.docker.com|mirrors.aliyun.com/docker-ce|g' /etc/yum.repos.d/docker-ce.repo
        fi
    fi

    info "Docker 软件源配置完成"
}

#-------------------- 安装 Docker --------------------
install_docker() {
    info "开始安装 Docker Engine..."
    echo ""

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        $SUDO $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    # 启动并设置开机自启
    $SUDO systemctl start docker
    $SUDO systemctl enable docker

    info "Docker Engine 安装完成！"
}

#-------------------- 配置国内镜像加速 --------------------
configure_mirror() {
    if [[ "$REGION" != "china" ]]; then
        info "国外环境，跳过镜像加速配置"
        return
    fi

    info "配置国内 Docker 镜像加速源..."
    
    # 备份旧配置
    if [[ -f /etc/docker/daemon.json ]]; then
        $SUDO cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)
        warn "已备份旧的 daemon.json"
    fi

    # 写入国内镜像加速配置
    $SUDO mkdir -p /etc/docker
    $SUDO tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.m.daocloud.io",
        "https://docker.xuanyuan.me"
    ]
}
EOF

    # 重新加载配置并重启 Docker
    $SUDO systemctl daemon-reload
    $SUDO systemctl restart docker

    # 验证配置
    echo ""
    info "验证镜像加速配置..."
    if $SUDO docker info 2>/dev/null | grep -q "Registry Mirrors"; then
        echo -e "  ${GREEN}✓${NC} 镜像加速配置已生效"
        $SUDO docker info 2>/dev/null | grep -A 5 "Registry Mirrors" | while read -r line; do
            echo -e "    ${CYAN}${line}${NC}"
        done
    else
        warn "未能验证镜像加速配置，请手动检查"
    fi
}

#-------------------- 非 root 用户配置 --------------------
configure_user() {
    echo ""
    echo -n "是否将当前用户 $(whoami) 添加到 docker 组？(Y/n): "
    read -r add_user
    if [[ ! "$add_user" =~ ^[Nn]$ ]]; then
        $SUDO usermod -aG docker "$(whoami)"
        info "已将用户 $(whoami) 添加到 docker 组"
        warn "请注销并重新登录以使用户组生效，之后可直接运行 docker 命令"
    fi
}

#-------------------- 验证安装 --------------------
verify_installation() {
    separator
    info "验证 Docker 安装..."
    echo ""

    # Docker 版本
    echo -e "  ${BLUE}Docker 版本：${NC}"
    docker --version 2>/dev/null || $SUDO docker --version

    echo ""

    # Docker Compose 版本
    echo -e "  ${BLUE}Docker Compose 版本：${NC}"
    docker compose version 2>/dev/null || $SUDO docker compose version

    echo ""

    # Docker 服务状态
    echo -e "  ${BLUE}Docker 服务状态：${NC}"
    if $SUDO systemctl is-active --quiet docker; then
        echo -e "    ${GREEN}● 运行中${NC}"
    else
        echo -e "    ${RED}● 未运行${NC}"
        warn "Docker 服务未正常启动，请尝试：sudo systemctl start docker"
    fi

    # 测试运行 hello-world
    echo ""
    echo -n "  是否运行 hello-world 容器测试安装？(Y/n): "
    read -r run_test
    if [[ ! "$run_test" =~ ^[Nn]$ ]]; then
        echo ""
        info "正在拉取并运行 hello-world 镜像..."
        if docker run --rm hello-world 2>/dev/null || $SUDO docker run --rm hello-world 2>/dev/null; then
            echo -e "\n  ${GREEN}✓ Docker 安装验证成功！${NC}"
        else
            warn "hello-world 测试未成功，可能是网络问题，请检查配置"
        fi
    fi
}

#-------------------- 完成 --------------------
print_summary() {
    separator
    echo -e "${GREEN}${BOLD}           Docker 安装完成！${NC}"
    separator
    echo ""
    echo -e "  ${BLUE}常用命令：${NC}"
    echo -e "    docker --version                   # 查看版本"
    echo -e "    docker ps                          # 查看运行中的容器"
    echo -e "    docker compose version              # 查看 Compose 版本"
    echo -e "    sudo systemctl status docker       # 查看 Docker 服务状态"
    echo -e "    sudo systemctl start/stop docker   # 启动/停止 Docker"
    echo -e "    sudo journalctl -u docker           # 查看日志"
    echo ""
    if [[ "$REGION" == "china" ]]; then
        echo -e "  ${BLUE}镜像加速源：${NC}"
        echo -e "    https://docker.1ms.run"
        echo -e "    https://docker.m.daocloud.io"
        echo -e "    https://docker.xuanyuan.me"
    fi
    echo ""
    echo -e "  ${YELLOW}如需卸载：${NC}"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        echo -e "    sudo apt-get purge docker-ce docker-ce-cli containerd.io"
    else
        echo -e "    sudo $PKG_MANAGER remove docker-ce docker-ce-cli containerd.io"
    fi
    echo -e "    sudo rm -rf /var/lib/docker /var/lib/containerd"
    separator
}

#-------------------- 主流程 --------------------
main() {
    echo ""
    detect_os
    choose_region
    remove_old_docker
    install_dependencies
    setup_repo
    install_docker
    configure_mirror
    configure_user
    verify_installation
    print_summary
}

# 运行主函数
main
