# ASU OpenWrt 一键部署

一键部署 OpenWrt ASU (Attended SysUpgrade) 云编译系统，支持 ImmortalWrt 插件源。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)](openwrt.sh)

## ✨ 特性

- 🚀 **一键部署** - 单脚本完成全部配置
- 🔧 **ImmortalWrt 支持** - 内置插件源
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
| **网络** | 需要互联网 | 稳定连接 |

## 🚀 快速开始

### 1. 传输脚本到服务器

```bash
# 本地执行（Windows/macOS/Linux）
scp openwrt.sh user@your-server:~/
```

### 2. SSH 登录并执行

```bash
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

## 📂 文件结构

```
.
├── openwrt.sh          # 一键部署脚本
├── README.md           # 本文档
└── LICENSE             # MIT 许可证
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

### 5. ImageBuilder 镜像拉取失败

```bash
# 检查网络连接
ping downloads.openwrt.org

# 手动拉取测试
podman pull ghcr.io/openwrt/imagebuilder:mediatek-filogic-latest
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

### v1.0 (2024-07-18)
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
