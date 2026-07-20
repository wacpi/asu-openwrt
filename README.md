# ASU OpenWrt 一键部署

> **OpenWrt 最新固件 + ImmortalWrt 丰富插件源，一台自建服务器全搞定。**  
> 自建 ASU 云编译系统，自由选择固件版本与第三方软件源，高度自定义预装包。
一键部署 OpenWrt ASU (Attended SysUpgrade) 云编译系统，支持 ImmortalWrt 插件源。

> ⚠️ **免责声明 · 使用前必读**
>
> **本项目的定位：** 让你用上官方 OpenWrt 固件的同时，能额外安装一些 OpenWrt 官方源没有、但 ImmortalWrt 源提供的插件和软件包。
>
> **本项目只做一件事：** 仅追加 ImmortalWrt 的 `luci` 和 `packages` 两个软件源（**不含** `routing`、`base`、`kmods` 等内核级/底层依赖包），确保 ASU 能识别这些源中的软件包供你选择安装。
>
> **本项目不提供：**
> - ❌ OpenWrt 或 ImmortalWrt 的技术支持和故障解决
> - ❌ 因混用两方源导致的系统崩溃、功能异常、包冲突等问题的排查与修复
>
> **上游也不管：**
> - 🔒 **OpenWrt 官方**不会为这种混源做法提供支持
> - 🔒 **ImmortalWrt 官方**也不会为这种混源做法提供支持
>
> **当前测试结论：**
> - ✅ `luci` 和 `packages` 源中的软件包（OpenWrt 架构兼容的前提下）目前未发现导致系统崩溃的问题
> - ⚠️ 但不排除个别插件存在功能兼容性差异，**这不等于 100% 兼容**
> - 如果选择了仅 ImmortalWrt 特有、与 OpenWrt 内核/ABI 不兼容的包，**可能导致固件构建失败或系统不可用**
>
> **使用建议：**
> - 了解你的需求，确认所选包不在内核/驱动层面依赖 ImmortalWrt 特有修改
> - 出问题不要找 ImmortalWrt 群，也不要找 OpenWrt 社区——**两边都不会接**
> - **自己测试，自己兜底**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)](openwrt.sh)

## ✨ 特性

- 🚀 **一键部署** - 单脚本完成全部配置
- 🔧 **ImmortalWrt 支持** - 内置插件源，随 OpenWrt 版本自动匹配
- 🌐 **Web 界面** - Firmware Selector 前端
- 🔒 **安全隔离** - Podman rootless 容器
- ⚡ **自动构建** - 支持多设备/多版本固件编译

## 📋 系统要求

| 项目 | 最低要求 | 推荐配置 |
|------|----------|----------|
| **系统** | Ubuntu 22.04 LTS | Ubuntu 24.04/26.04 LTS |
| **内存** | 4 GB | 8 GB+ |
| **硬盘** | 20 GB | 50 GB+ |
| **CPU** | 2 核 | 4 核+ |
| **网络** | 10 Mbps | 50 Mbps+ |

## 🚀 快速开始

### 1. 直接远程执行

```bash
# 方式 A：下载后执行（推荐，兼容性最好）
curl -sSLO https://raw.githubusercontent.com/wacpi/asu-openwrt/master/openwrt.sh
chmod +x openwrt.sh
./openwrt.sh

# 方式 B：管道一键执行（快捷，部分系统可能因编码问题报错）
# bash <(curl -sSL https://raw.githubusercontent.com/wacpi/asu-openwrt/master/openwrt.sh)
```

### 2. 或先传输再执行

```bash
# 本地执行（Windows/macOS/Linux）
scp openwrt.sh user@your-server:~/

# SSH 登录
ssh user@your-server

# 赋予执行权限
chmod +x openwrt.sh

# 一键部署（预计 10-30 分钟）
./openwrt.sh
```

### 3. 访问系统

部署完成后，脚本会显示访问地址：

```
=========================================
  部署完成！
=========================================

  统一入口: http://your-server-ip:80

  服务状态:
    nginx:        active
    asu-redis     Up
    asu-server    Up
    asu-worker    Up

=========================================
```

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    你的服务器                             │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Redis        │  │ ASU Server   │  │ ASU Worker   │  │
│  │ (缓存/队列)  │  │ (API 服务)   │  │ (固件构建)   │  │
│  │ :6379        │  │ :8000        │  │              │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                         │                   │            │
│                         ▼                   ▼            │
│              ┌─────────────────────────────────────┐    │
│              │     OpenWrt ImageBuilder             │    │
│              │     (自动选择最新版本)                │    │
│              └─────────────────────────────────────┘    │
│                         │                               │
│                         ▼                               │
│              ┌─────────────────────────────────────┐    │
│              │         生成固件                      │    │
│              │      sysupgrade.bin/itb              │    │
│              └─────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## 🔧 自定义配置

### ImmortalWrt 插件源

脚本默认配置了 ImmortalWrt 官方源：

```toml
repository_allow_list = [
    "https://downloads.immortalwrt.org/",
]
```

### 自定义插件

在 Web 界面选择固件时，可以添加自定义包。常见插件类型：

| 类型 | 说明 |
|------|------|
| **系统工具** | LuCI 界面、中文语言包 |
| **网络服务** | DNS、DDNS、UPnP |
| **管理工具** | 系统监控、流量统计 |

> 💡 具体可用插件取决于 ImmortalWrt 源中的软件包

> 💡 设备型号由 OpenWrt/ImmortalWrt 上游项目决定，脚本部署后在 Web 界面选择即可

## 🔐 第三方软件源签名验证

OpenWrt 25.12+ 的 ImageBuilder 使用 APK 包管理器，默认强制开启包签名验证（`CONFIG_SIGNATURE_CHECK=y`）。
添加 ImmortalWrt 等第三方源时，APK 需要找到对应的公钥才能验证包签名。

### 方案原理

不修改 ASU 或 ImageBuilder 代码，不绕过签名检查。通过 Podman 自身的 `containers.conf` 机制注入
`APK_KEYS` 环境变量，让 ImageBuilder 的 Makefile 在调用 apk 时指向正确的密钥目录：

```
rootfs.mk 中 apk 函数定义:
    --keys-dir $(if $(APK_KEYS),$(APK_KEYS),$(TOPDIR))

链路:
  ~/.config/containers/containers.conf
    → Podman 创建构建容器时自动注入 APK_KEYS=/builder/keys
      → ImageBuilder 容器内 Make 从环境继承 $(APK_KEYS)
        → apk --keys-dir /builder/keys ...
          → /builder/keys/ 内有前端 asu_repository_keys 传入的 ImmortalWrt 公钥
            → APK 正常验证 ImmortalWrt 包签名，无 UNTRUSTED 错误
```

### 涉及文件

| 文件 | 来源 | 操作 | 作用 |
|------|------|------|------|
| `~/.config/containers/containers.conf` | Podman 配置，脚本新增 | **创建** | 注入 `APK_KEYS=/builder/keys` 到所有构建容器 |
| `asu/asu/build.py` | ASU 上游 | **不动** | worker 调用 `inject_files()` 将前端密钥写入 `/builder/keys/` |
| `asu/asu.toml` | ASU 配置，脚本模板生成 | **创建** | 配置 `cache_url`、`repository_allow_list`、`base_container` 等 |
| `firmware-selector/www/config.js` | 前端配置，脚本模板生成 | **创建** | 定义 ImmortalWrt 源 URL、公钥 (`asu_repository_keys`) |
| `include/rootfs.mk` | ImageBuilder 内部 | **不动** | 定义 apk 函数，`APK_KEYS` 控制 `--keys-dir` 路径 |
| `include/image.mk` | ImageBuilder 内部 | **不动** | 定义 `$(if $(CONFIG_SIGNATURE_CHECK),,--allow-untrusted)` |

### 与旧方案对比

| | 旧方案 | 新方案 |
|--|--------|--------|
| 方法 | 容器内 sed `.config` 注释 `CONFIG_SIGNATURE_CHECK` | `containers.conf` 注入 `APK_KEYS` 环境变量 |
| 产物 | `build-patched.py` + volume mount 覆盖原始 `build.py` | 无代码 patch |
| 签名 | **绕过**（`--allow-untrusted`） | **保留**（放入正确公钥路径） |
| 侵入性 | 修改 ASU 源码行为 | 零侵入，纯 Podman 配置 |

## 📂 文件结构

```
.
├── openwrt.sh          # 一键部署脚本
├── README.md           # 本文档
├── LICENSE             # MIT 许可证
└── (部署后)
    ├── ~/.config/containers/containers.conf   # Podman 容器默认环境变量
    ├── ~/immortalwrt-cloud/
    │   ├── asu/asu.toml                       # ASU 后端配置
    │   ├── asu/asu/                           # ASU 源码（未修改）
    │   ├── firmware-selector/www/config.js    # 前端配置
    │   └── public/store/                      # 构建产物
    └── /etc/nginx/sites-available/firmware-selector  # nginx 反向代理配置
```

## 🔍 服务管理

### 查看服务状态

```bash
# 查看容器状态
podman ps

# 查看 nginx 状态
sudo systemctl status nginx
```

### 查看日志

```bash
# ASU Server 日志
podman logs asu-server --tail 50

# ASU Worker 日志（构建过程）
podman logs asu-worker --tail 50

# nginx 日志
sudo journalctl -u nginx -f
```

### 重启服务

```bash
# 重启所有 ASU 服务
podman restart asu-redis asu-server asu-worker

# 重启 nginx
sudo systemctl restart nginx
```

### 停止服务

```bash
podman stop asu-redis asu-server asu-worker
sudo systemctl stop nginx
```

### 清理构建缓存

```bash
# 进入 ASU 目录
cd ~/immortalwrt-cloud

# 清理构建产物
rm -rf public/store/*

# 清理 Redis 缓存
rm -rf redis-data/*
podman restart asu-redis
```

## ❓ 常见问题

### 1. 构建失败：内存不足

```bash
# 添加 4GB swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 永久生效
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 2. Redis 连接失败

```bash
# 检查 Redis 是否运行
podman ps | grep redis

# 重启 Redis
podman restart asu-redis
```

### 3. nginx 403 错误

```bash
# 修复权限
sudo usermod -aG $USER www-data
chmod 755 ~
chmod -R 755 ~/immortalwrt-cloud/firmware-selector/www
sudo systemctl restart nginx
```

### 4. 无法访问 Web 界面

```bash
# 检查端口占用
ss -tlnp | grep :80
ss -tlnp | grep :8000

# 检查防火墙
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 8000/tcp
```

### 5. 固件构建失败

```bash
# 查看 Worker 日志
podman logs asu-worker --tail 50

# 清理缓存重试
cd ~/immortalwrt-cloud
rm -rf public/store/*
podman restart asu-worker
```

## 🐛 故障排查流程

```
问题
  │
  ├─→ Web 界面无法访问？
  │     ├─→ nginx 运行？ → sudo systemctl status nginx
  │     ├─→ 端口占用？ → ss -tlnp | grep :80
  │     └─→ 防火墙？ → sudo ufw status
  │
  ├─→ API 返回错误？
  │     ├─→ ASU Server 运行？ → podman ps | grep asu-server
  │     ├─→ Redis 连接？ → podman exec asu-redis redis-cli ping
  │     └─→ 查看日志 → podman logs asu-server --tail 50
  │
  └─→ 固件构建失败？
        ├─→ Worker 运行？ → podman ps | grep asu-worker
        ├─→ 查看构建日志 → podman logs asu-worker --tail 100
        └─→ 清理重试 → rm -rf public/store/* && podman restart asu-worker
```

## 📝 更新日志

### v1.1 (2026-07-19)
- 🔧 修复：CRLF 自修复失败需执行两次的问题
- 🔧 修复：`source` 不存在文件导致脚本中断
- 🔧 修复：`apt-get` 静默安装吞掉错误信息
- 🔧 修复：Ctrl+C 中断后留下孤儿容器（添加 trap 清理）
- 🔧 修复：容器重启后不会自动恢复（systemd user service）
- 🚀 改进：ImmortalWrt 插件源版本自适应，不再硬编码 `packages-25.12`
- 📖 文档：更新快速开始，支持 `curl | bash` 一键远程执行

### v1.0 (2026-07-18)
- ✨ 初始版本
- ✨ 支持 ImmortalWrt 插件源
- ✨ Podman rootless 部署
- ✨ nginx 反向代理
- ✨ 自动验证部署

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

[MIT License](LICENSE)

## 🔗 相关项目

- [OpenWrt ASU](https://github.com/openwrt/asu) - 官方 ASU 后端
- [Firmware Selector](https://github.com/openwrt/firmware-selector-openwrt-org) - 官方前端
- [ImmortalWrt](https://immortalwrt.org/) - ImmortalWrt 项目
- [Podman](https://podman.io/) - 无守护进程的容器引擎

## ⭐ 支持

如果这个项目对你有帮助，请给个 Star ⭐

---

**Made with ❤️ for OpenWrt community**
