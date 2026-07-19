#!/bin/bash
# ASU + Firmware Selector 一键部署脚本
# 目标: OpenWrt ASU + ImmortalWrt 插件源 + 前端
# 适用: Ubuntu 22.04/24.04/26.04 LTS
set -euo pipefail

# ========== 工具函数 ==========
log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
err() { echo -e "\033[1;31m[$(date '+%H:%M:%S')] ERROR: $*\033[0m"; exit 1; }

# ========== 配置 ==========
ASU_DIR="$HOME/immortalwrt-cloud"
ASU_REPO="https://github.com/openwrt/asu.git"
FRONTEND_REPO="https://github.com/openwrt/firmware-selector-openwrt-org.git"
VM_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
if [ -z "$VM_IP" ]; then
    VM_IP=$(hostname -I | awk '{print $1}')
fi

# ImmortalWrt 包架构（用于插件源）
# 常见架构: aarch64_cortex-a53 (ARM64), x86_64 (x86), mips_24kc (MIPS)
ARCH="aarch64_cortex-a53"

# ========== [1/7] 系统依赖 ==========
log "[1/7] 安装系统依赖..."

# 修复可能被中断的 dpkg
sudo dpkg --configure -a 2>/dev/null || true

sudo apt-get update -qq
sudo apt-get install -y -qq podman podman-compose python3 python3-venv git jq curl >/dev/null 2>&1
log "  ✓ 依赖安装完成"

# 强制优先使用 IPv4（部分服务器的 IPv6 出口在建立 TLS 连接时不稳定，
# 拉取 Docker Hub 镜像时容易出现 "connection reset by peer"，
# 这里让 glibc 的地址选择算法优先返回 IPv4 地址，避免走不通的 IPv6 通道）
if ! grep -q '^precedence ::ffff:0:0/96' /etc/gai.conf 2>/dev/null; then
    echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf > /dev/null
    log "  ✓ 已配置系统优先使用 IPv4（/etc/gai.conf）"
else
    log "  ✓ 系统已配置优先使用 IPv4，跳过"
fi

# ========== [2/7] Podman 配置 ==========
log "[2/7] 配置 Podman..."

# 配置 Docker Hub 镜像加速（国内 Docker Hub 直连不稳定）
MIRROR_CONF="/etc/containers/registries.conf.d/docker-mirror.conf"
if [ ! -f "$MIRROR_CONF" ]; then
    sudo tee "$MIRROR_CONF" > /dev/null << 'MIRROR'
[[registry]]
location = "docker.io"

[[registry.mirror]]
location = "docker.1ms.run"

[[registry.mirror]]
location = "docker.xuanyuan.me"
MIRROR
    log "  ✓ Docker Hub 镜像加速已配置"
else
    log "  ✓ Docker Hub 镜像加速已存在，跳过"
fi

# 启用 podman socket（worker 需要它来创建构建容器）
sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true
systemctl --user enable --now podman.socket 2>/dev/null || true

# 等待 socket 就绪
for i in {1..10}; do
    if [ -S "/run/user/$(id -u)/podman/podman.sock" ]; then
        break
    fi
    sleep 1
done

if [ ! -S "/run/user/$(id -u)/podman/podman.sock" ]; then
    err "podman.socket 启动失败，请手动运行: systemctl --user enable --now podman.socket"
fi
log "  ✓ podman.socket 已就绪"

# 创建构建隔离网络
# 注意：此网络目前只是创建出来，asu.toml 和下方 worker 容器启动命令
# 都没有引用它，因此实际构建容器不会被隔离在这个网络里。
# 如果需要真正的构建隔离，需确认 ASU 是否支持类似 build_network 的配置项，
# 并在 asu.toml 中显式指定，否则这一步等同于空操作。
podman network create asu-build 2>/dev/null || true
log "  ✓ asu-build 网络已创建（当前未被 worker 实际使用，见上方注释）"

# ========== [3/7] 克隆仓库 ==========
log "[3/7] 克隆仓库..."
mkdir -p "$ASU_DIR"
cd "$ASU_DIR"

if [ ! -d "asu" ]; then
    git clone --depth 1 "$ASU_REPO" asu
    log "  ✓ ASU 后端已克隆"
else
    log "  ✓ ASU 后端已存在"
fi

if [ ! -d "firmware-selector" ]; then
    git clone --depth 1 "$FRONTEND_REPO" firmware-selector
    log "  ✓ 前端已克隆"
else
    log "  ✓ 前端已存在"
fi

# ========== [4/7] 配置 ASU ==========
log "[4/7] 配置 ASU..."

cd "$ASU_DIR/asu"

# 创建 asu.toml
cat > asu.toml << 'ASUTOML'
# ASU 配置
upstream_url = "https://downloads.openwrt.org"
allow_defaults = true
log_level = "INFO"

# ImageBuilder 容器镜像
base_container = "ghcr.io/openwrt/imagebuilder"

# 构建缓存 TTL
build_ttl = "7d"
build_ttl_unversioned = "24h"
build_defaults_ttl = "30m"
build_failure_ttl = "1h"
max_pending_jobs = 200
job_timeout = "30m"

# 允许用户自定义仓库（ImmortalWrt 插件源）
repository_allow_list = [
    "https://downloads.immortalwrt.org/",
]
ASUTOML

# 记录真实 podman.sock 路径（worker 直接挂载真实路径，不用软链接中转，
# 避免部分 podman/docker 版本对 volume 为符号链接的处理不一致导致挂载失败）
PODMAN_SOCK="/run/user/$(id -u)/podman/podman.sock"

# 创建目录
mkdir -p public/store redis-data
log "  ✓ asu.toml + 目录已创建"

# ========== [5/7] 配置前端 ==========
log "[5/7] 配置前端..."

cd "$ASU_DIR/firmware-selector/www"

cat > config.js << 'CONFIGJS'
/* ASU Firmware Selector 配置 */
var config = {
  show_help: true,
  image_url: "https://downloads.openwrt.org",
  // nginx 反向代理同源，无需 CORS
  asu_url: "http://VM_IP_PLACEHOLDER",
  asu_extra_packages: ["luci-i18n-base-zh-cn", "luci-i18n-firewall-zh-cn", "luci-i18n-package-manager-zh-cn", "block-mount", "bridger", "kmod-nf-nathelper", "luci-app-statistics", "collectd-mod-thermal"],
  asu_repositories: {
    "immortalwrt_luci": "https://downloads.immortalwrt.org/releases/packages-25.12/ARCH_PLACEHOLDER/luci/packages.adb",
    "immortalwrt_packages": "https://downloads.immortalwrt.org/releases/packages-25.12/ARCH_PLACEHOLDER/packages/packages.adb",
  },
  asu_repositories_mode: "append",
  asu_repository_keys: [
    "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEHWuRPmchzSKwenEyU7Og06A7Fi5s\nkJ2yc3B/0+CboE4Gd2DLuJGdq2E7qX8fqyb2+EJgwmBUadshKA0hET7EjA==\n-----END PUBLIC KEY-----",
  ],
  info_url: "https://openwrt.org/start?do=search&id=toh&q={title} @toh",
};
CONFIGJS

# 替换占位符
sed -i "s|VM_IP_PLACEHOLDER|$VM_IP|g" config.js
sed -i "s|ARCH_PLACEHOLDER|$ARCH|g" config.js
log "  ✓ config.js 已创建（指向 $VM_IP:8000）"

# ========== [6/7] 构建镜像 + 启动服务 ==========
log "[6/7] 构建镜像 + 启动服务..."

cd "$ASU_DIR/asu"

# 优先直接拉取官方预构建镜像（Docker Hub 上已有现成的 openwrt/asu:latest），
# 避免本地构建时因为 uv.lock 缺失/版本不一致等仓库自身构建配置问题导致失败。
# 只有拉取失败（比如镜像被下架）时才回退到本地构建。
if podman image exists openwrt/asu:latest 2>/dev/null; then
    log "  ✓ ASU 镜像已存在，跳过拉取/构建"
elif podman pull docker.io/openwrt/asu:latest; then
    log "  ✓ 已从 Docker Hub 拉取官方 ASU 镜像"
else
    log "  ⚠️ 拉取官方镜像失败，回退为本地构建..."

    # ASU 的 Dockerfile 用 `uv sync --frozen` 安装依赖，这要求仓库里必须有 uv.lock。
    # 如果浅克隆到的这个提交缺少锁文件（或和 pyproject.toml 不同步），
    # 这里提前用 uv 生成一份，避免 build 中途因为 --frozen 报错。
    if [ ! -f uv.lock ]; then
        log "  未找到 uv.lock，先在宿主机生成锁文件..."
        if ! command -v uv >/dev/null 2>&1; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
            # shellcheck disable=SC1090
            source "$HOME/.local/bin/env" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
        fi
        uv lock
        log "  ✓ uv.lock 已生成"
    fi

    log "  构建 ASU 镜像（约 3-5 分钟）..."
    podman build -t openwrt/asu:latest .
    log "  ✓ ASU 镜像构建完成"
fi

# 清理已存在的旧容器
for c in asu-redis redis asu-server asu-worker; do
    if podman ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
        log "  清理旧容器: $c"
        podman rm -f "$c" 2>/dev/null || true
    fi
done

# 启动 Redis
log "  启动 Redis..."
podman run -d \
    --name asu-redis \
    --restart always \
    --network host \
    -v "$(pwd)/redis-data:/data:rw" \
    docker.io/library/redis:7-alpine \
    redis-server --bind 127.0.0.1

# 等待 Redis 就绪
for i in {1..15}; do
    if podman exec asu-redis redis-cli ping 2>/dev/null | grep -q PONG; then
        break
    fi
    sleep 1
done
if ! podman exec asu-redis redis-cli ping 2>/dev/null | grep -q PONG; then
    err "Redis 启动失败"
fi
log "  ✓ Redis 已就绪"

# 启动 ASU Server
log "  启动 ASU Server..."
podman run -d \
    --name asu-server \
    --restart always \
    --network host \
    -v "$(pwd)/asu.toml:/app/asu.toml:ro" \
    -v "$(pwd)/public:/public:rw" \
    -e ASU_SERVER_CONFIG=/app/asu.toml \
    openwrt/asu:latest \
    uv run uvicorn --host 0.0.0.0 asu.main:app

# 启动 ASU Worker
log "  启动 ASU Worker..."
podman run -d \
    --name asu-worker \
    --restart always \
    --network host \
    -v "$(pwd)/asu.toml:/app/asu.toml:ro" \
    -v "$(pwd)/public:/public:rw" \
    -v "$PODMAN_SOCK:/var/podman.sock:rw" \
    -e ASU_SERVER_CONFIG=/app/asu.toml \
    openwrt/asu:latest \
    uv run rq worker --logging_level INFO

# 安装 nginx（反向代理，解决 CORS 跨域问题）
log "  配置 nginx 反向代理..."
sudo apt-get install -y -qq nginx >/dev/null 2>&1

# 修复 nginx 403：让 www-data 用户有权限读取当前用户 home 目录下的文件
# 注意：使用当前登录用户名而非写死的用户名，脚本才能在任意用户下通用
CURRENT_USER="$(whoami)"
sudo usermod -aG "$CURRENT_USER" www-data
chmod 755 "$HOME"
chmod -R 755 "$ASU_DIR/firmware-selector/www"

# 写入 nginx 配置（这里不能用引号包裹的 heredoc 'NGINX'，否则 $ASU_DIR 不会被替换）
sudo tee /etc/nginx/sites-available/firmware-selector > /dev/null << NGINX
server {
    listen 80;
    server_name _;

    # 前端静态文件
    root $ASU_DIR/firmware-selector/www;
    index index.html;

    # ASU 后端 API 代理（同源，无 CORS 问题）
    location /json/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_connect_timeout 10s;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 600s;
        proxy_connect_timeout 10s;
        client_max_body_size 50M;
    }

    location /store/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 600s;
        proxy_connect_timeout 10s;
    }
}
NGINX

# 启用站点
sudo ln -sf /etc/nginx/sites-available/firmware-selector /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx
sudo systemctl restart nginx
log "  ✓ nginx 反向代理已配置（端口 80）"

log "  ✓ 所有服务已启动"

# ========== [7/7] 验证 ==========
log "[7/7] 验证部署..."

# 等待 server 启动
for i in {1..30}; do
    if curl -s "http://127.0.0.1:8000/json/v1/branches.json" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# 测试 branches.json
BRANCHES=$(curl -s "http://127.0.0.1:8000/json/v1/branches.json" 2>/dev/null)
if echo "$BRANCHES" | jq . >/dev/null 2>&1; then
    BRANCH_COUNT=$(echo "$BRANCHES" | jq 'length')
    log "  ✓ branches.json 正常（$BRANCH_COUNT 个分支）"
else
    log "  ✗ branches.json 异常"
    podman logs asu-server --tail 10
fi

# 测试 overview.json
OVERVIEW=$(curl -s "http://127.0.0.1:8000/json/v1/overview.json" 2>/dev/null)
if echo "$OVERVIEW" | jq . >/dev/null 2>&1; then
    log "  ✓ overview.json 正常"
else
    log "  ✗ overview.json 异常"
fi

# 测试 profile API（端到端验证：版本 → 目标 → 设备）
LATEST=$(echo "$OVERVIEW" | jq -r '.latest[0]' 2>/dev/null)
if [ -n "$LATEST" ] && [ "$LATEST" != "null" ]; then
    PROFILE_URL="http://127.0.0.1:8000/json/v1/releases/$LATEST/targets/mediatek/filogic/netcore_n60-pro.json"
    if curl -s "$PROFILE_URL" | jq -e '.titles' >/dev/null 2>&1; then
        log "  ✓ Profile API 正常: mediatek/filogic (OpenWrt $LATEST)"
    else
        log "  ⚠️ Profile API 测试跳过（可手动验证）"
    fi
else
    log "  ⚠️ 无法获取最新版本号，跳过 profile 测试"
fi

# 测试前端（通过 nginx 代理）
if curl -s "http://127.0.0.1:80/" | grep -q "Firmware Selector" 2>/dev/null; then
    log "  ✓ 前端页面正常"
else
    log "  ✗ 前端页面异常"
fi

# 测试 nginx 代理 ASU API（同源验证）
if curl -s "http://127.0.0.1:80/json/v1/branches.json" | jq -e 'length' >/dev/null 2>&1; then
    log "  ✓ nginx 代理 ASU API 正常"
else
    log "  ✗ nginx 代理 ASU API 异常"
fi

# ========== 完成 ==========
echo ""
echo "========================================="
echo "  部署完成！"
echo "========================================="
echo ""
echo "  统一入口: http://$VM_IP"
echo ""
echo "  服务状态:"
echo "    nginx:        $(systemctl is-active nginx)"
podman ps --format '    {{.Names}}\t{{.Status}}' 2>/dev/null
echo ""
echo "  架构: 浏览器 → nginx(:80) → 前端静态文件 + /json/* → ASU(:8000)"
echo ""
echo "  查看日志:"
echo "    podman logs asu-server --tail 20"
echo "    podman logs asu-worker --tail 20"
echo "    sudo journalctl -u nginx -f"
echo ""
echo "========================================="
