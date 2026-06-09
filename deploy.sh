#!/bin/bash
# FreeChat + FreeLLMAPI 一键部署脚本
# 在腾讯云服务器上运行

set -e

echo "=== FreeChat 部署脚本 ==="

# 1. 部署 freellmapi
echo ""
echo "[1/3] 部署 FreeLLMAPI..."
if [ -d "$HOME/freellmapi" ]; then
    echo "  FreeLLMAPI 目录已存在，跳过克隆"
else
    git clone https://github.com/tashfeenahmed/freellmapi.git "$HOME/freellmapi"
fi

cd "$HOME/freellmapi"

# 生成 .env
if [ ! -f .env ]; then
    ENCRYPTION_KEY="$(openssl rand -hex 32)"
    printf "ENCRYPTION_KEY=%s\nPORT=3003\nHOST_BIND=127.0.0.1\n" "$ENCRYPTION_KEY" > .env
    echo "  已生成 .env（端口 3003）"
else
    echo "  .env 已存在，跳过"
fi

# 启动
if command -v docker &>/dev/null; then
    echo "  使用 Docker 启动..."
    docker compose up -d 2>/dev/null || docker-compose up -d
elif command -v node &>/dev/null; then
    echo "  使用 Node.js 启动..."
    npm install --production 2>/dev/null
    # 后台运行
    if command -v pm2 &>/dev/null; then
        pm2 start npm --name freellmapi -- start
    else
        nohup npm start > /tmp/freellmapi.log 2>&1 &
        echo "  PID: $!"
    fi
else
    echo "  错误：需要 Docker 或 Node.js"
    exit 1
fi

# 2. 部署 FreeChat 静态文件
echo ""
echo "[2/3] 部署 FreeChat..."
FREECHAT_DIR="/var/www/freechat"
sudo mkdir -p "$FREECHAT_DIR"

# 检查当前目录是否有 free-chat 文件
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/free-chat/index.html" ]; then
    sudo cp "$SCRIPT_DIR/free-chat/"* "$FREECHAT_DIR/"
elif [ -f "/root/.openclaw/workspace/free-chat/index.html" ]; then
    sudo cp /root/.openclaw/workspace/free-chat/* "$FREECHAT_DIR/"
else
    echo "  请将 free-chat 目录拷贝到服务器，然后重新运行"
    exit 1
fi

sudo chown -R www-data:www-data "$FREECHAT_DIR" 2>/dev/null || true
echo "  已部署到 $FREECHAT_DIR"

# 3. Nginx 配置
echo ""
echo "[3/3] 配置 Nginx..."

NGINX_CONF="/etc/nginx/sites-available/freechat"
if [ -f "$NGINX_CONF" ]; then
    echo "  Nginx 配置已存在，跳过"
else
    sudo tee "$NGINX_CONF" > /dev/null << 'NGINX'
# FreeChat
location /chat/ {
    alias /var/www/freechat/;
    try_files $uri $uri/ /chat/index.html;

    # SSE 支持
    proxy_buffering off;
    proxy_cache off;
}

# FreeLLMAPI
location /llmapi/ {
    proxy_pass http://127.0.0.1:3003/;
    proxy_http_version 1.1;
    proxy_set_header Connection "";

    # SSE 支持
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 300s;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
NGINX

    # 插入到 default server block
    if [ -f /etc/nginx/sites-available/default ]; then
        # 在 server block 的最后一个 } 之前插入
        sudo sed -i '/^[[:space:]]*}[[:space:]]*$/i # FreeChat & FreeLLMAPI (added by deploy script)\n' /etc/nginx/sites-available/default
        # 实际用 include 更好，这里简化处理
        echo "  请手动将以下配置添加到 Nginx server block:"
        echo ""
        cat "$NGINX_CONF"
        echo ""
    fi
fi

# 测试 Nginx
sudo nginx -t 2>/dev/null && sudo systemctl reload nginx && echo "  Nginx 已重载" || echo "  Nginx 配置有误，请手动检查"

echo ""
echo "=== 部署完成 ==="
echo ""
echo "访问地址："
echo "  FreeChat:    http://你的IP/chat/"
echo "  FreeLLMAPI:  http://你的IP/llmapi/"
echo ""
echo "首次使用："
echo "  1. 打开 FreeChat"
echo "  2. 点击 ⚙ 设置"
echo "  3. API 地址填: http://你的IP/llmapi"
echo "  4. API Key 填: 在 FreeLLMAPI 管理后台生成的 key"
echo ""
echo "手机使用："
echo "  浏览器打开 http://你的IP/chat/"
echo "  Safari: 分享 → 添加到主屏幕"
echo "  Chrome: 菜单 → 添加到主屏幕"
