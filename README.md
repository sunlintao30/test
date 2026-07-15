# 服务器运维脚本工具集

一套面向 Linux 服务器的运维管理脚本集合，覆盖系统优化、面板管理、网络组网、磁盘文件、远程下载与固件编译等常见场景。每个脚本均为独立的交互式菜单工具，开箱即用。

## 通用特性

- **交互式菜单**：所有脚本采用彩色 TUI 菜单，输入数字即可执行对应功能
- **跨发行版兼容**：自动识别 Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora 等，适配 `apt` / `yum` / `dnf` 包管理器
- **自动权限检测**：多数脚本需 root 权限，会提示使用 `sudo` 运行
- **配置备份**：修改系统配置前自动备份，支持一键恢复
- **统一运行方式**：
  ```bash
  chmod +x <脚本名>.sh
  sudo ./<脚本名>.sh
  ```

## 脚本目录

### 系统管理与优化

| 脚本 | 功能说明 |
| --- | --- |
| [system_info.sh](file:///workspace/system_info.sh) | 系统信息查看 & 测速 & 回程路由可视化。查看 CPU / 内存 / 存储 / 网络信息，集成 Speedtest 网速测试、NextTrace 回程路由可视化、流媒体解锁检测及综合跑分 |
| [linux_optimize.sh](file:///workspace/linux_optimize.sh) | Linux 系统优化脚本。内核参数调优、网络/TCP 优化、内存与 swap 管理、文件描述符限制、DNS 与磁盘 I/O 调度优化，支持一键全面优化与预设场景 |
| [ssh_manager.sh](file:///workspace/ssh_manager.sh) | SSH 安全管理脚本。修改端口、一键安全加固、安装配置 Fail2Ban 防暴力破解、密钥对生成与公钥管理、查看登录日志 |
| [bbr_manager.sh](file:///workspace/bbr_manager.sh) | BBR 拥塞控制算法管理工具。BBR 状态检查、启用/禁用、内核版本检测、参数调优 |
| [change_mirror.sh](file:///workspace/change_mirror.sh) | 系统软件源与 Docker 镜像源管理。查看当前源、切换国内外镜像源、自动选择最佳源、备份与恢复源配置 |
| [install_docker.sh](file:///workspace/install_docker.sh) | Docker CE 自动安装脚本。检测 OS 类型、选择国内外安装源、安装 Docker 并配置镜像加速 |

### 面板管理

| 脚本 | 功能说明 |
| --- | --- |
| [1panel_manager.sh](file:///workspace/1panel_manager.sh) | 1Panel Linux 服务器管理面板的安装、配置、备份与卸载，集成 BBR 状态检查与启用 |
| [xui_manager.sh](file:///workspace/xui_manager.sh) | 3X-UI 面板管理脚本（基于 Xray）。支持 VLESS/VMess/Trojan/Shadowsocks 多协议代理，面板安装、端口/路径/账户配置、HTTPS 设置、备份恢复与卸载 |

### 网络与组网

| 脚本 | 功能说明 |
| --- | --- |
| [easytier_manager.sh](file:///workspace/easytier_manager.sh) | EasyTier 组网管理。支持服务端/客户端模式部署，Docker 与原生部署，节点列表查看与服务管理 |
| [hysteria_manager.sh](file:///workspace/hysteria_manager.sh) | Hysteria 2 代理一键部署脚本。支持快速安装与 DIY 配置，多种 TLS / 认证 / 伪装 / 混淆模式，客户端信息输出与更新 |
| [mtproxy.sh](file:///workspace/mtproxy.sh) | MTProto Proxy 一键部署脚本（支持 Fake TLS 伪装）。Docker 方式与二进制方式部署，生成 Telegram 链接，端口/域名/密钥管理 |

### 磁盘与文件

| 脚本 | 功能说明 |
| --- | --- |
| [disk_mount.sh](file:///workspace/disk_mount.sh) | 网络磁盘挂载管理（SMB/WebDAV）。支持 systemd automount 自动挂载与断线重连 |
| [file_share.sh](file:///workspace/file_share.sh) | 文件共享服务器管理（多协议）。SMB/CIFS、NFS、FTP (vsftpd)、WebDAV、SFTP 一键安装与配置 |
| [file_sync.sh](file:///workspace/file_sync.sh) | 文件同步软件管理。Syncthing、rclone、Resilio Sync 安装部署与配置，支持同步工具对比 |
| [download_manager.sh](file:///workspace/download_manager.sh) | 远程下载工具安装与管理。Aria2、qBittorrent-nox、Transmission 的安装部署与统一管理 |

### 固件编译

| 脚本 | 功能说明 |
| --- | --- |
| [immortalwrt_build.sh](file:///workspace/immortalwrt_build.sh) | ImmortalWrt/OpenWrt 编译环境一键搭建脚本。环境检测、依赖安装、源码克隆、feeds 更新、配置与多线程编译优化，适配虚拟机/云服务器/WSL2 |

## 快速开始

仓库地址：https://github.com/sunlintao30/test

### 方式一：在线一键运行（推荐）

无需克隆仓库，直接执行主菜单脚本。主脚本会自动检测本地是否存在分支脚本：本地存在则本地执行，不存在则从在线地址下载到临时文件执行。

```bash
# curl 方式
curl -fsSL https://raw.githubusercontent.com/sunlintao30/test/main/main.sh | sudo bash

# wget 方式
wget -qO- https://raw.githubusercontent.com/sunlintao30/test/main/main.sh | sudo bash
```

单独运行某个分支脚本（以系统优化为例）：

```bash
curl -fsSL https://raw.githubusercontent.com/sunlintao30/test/main/linux_optimize.sh | sudo bash
```

### 方式二：本地克隆运行

```bash
# 1. 克隆仓库
git clone https://github.com/sunlintao30/test.git ~/ops-scripts && cd ~/ops-scripts

# 2. 赋予执行权限
chmod +x *.sh

# 3. 以 root 权限运行主菜单（统一入口）
sudo ./main.sh

# 也可直接运行单个分支脚本（以系统优化为例）
sudo ./linux_optimize.sh
```

每个脚本启动后会显示分类菜单与当前状态概览，按提示输入序号即可。

## 环境要求

- Linux 主流发行版（Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora）
- Bash 4.0+
- root 或 sudo 权限
- 部分脚本依赖网络连接以下载组件
