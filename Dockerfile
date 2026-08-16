# syntax=docker/dockerfile:1

FROM python:3.11-slim AS base

# 避免交互式配置
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 安装系统依赖：Chromium、Xvfb（Tkinter 无头）、中文字体、浏览器运行库
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    chromium-driver \
    xvfb \
    x11-utils \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libgtk-3-0 \
    tcl \
    tk \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 先复制依赖文件，利用 Docker 层缓存
COPY requirements.txt requirements-web.txt ./

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt -r requirements-web.txt

# 复制项目代码
COPY . .

# DrissionPage 环境变量：使用系统 Chromium，不自动下载
ENV DRISSIONPAGE_CHROMIUM_PATH=/usr/bin/chromium \
    DRISSIONPAGE_DOWNLOAD_BROWSER=false \
    DISPLAY=:99 \
    WEB_HOST=0.0.0.0 \
    WEB_PORT=8092

# 暴露 Web UI 端口
EXPOSE 8092

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -f http://localhost:8092/ || exit 1

# 启动脚本：先启动 Xvfb，再启动 Web 服务
COPY <<'EOF' /app/entrypoint.sh
#!/bin/bash
set -e

# 启动 Xvfb 虚拟显示（供 Tkinter / DrissionPage 使用）
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!

# 等待 Xvfb 就绪
sleep 1

# 清理函数
cleanup() {
    kill $XVFB_PID 2>/dev/null || true
}
trap cleanup EXIT

# 根据环境变量选择启动模式
if [ "${MODE:-web}" = "cli" ]; then
    # CLI 模式：python grok_register_ttk.py cli
    exec python grok_register_ttk.py cli "$@"
else
    # Web 模式：启动 FastAPI 控制平面
    exec python -m uvicorn web.server:app --host "${WEB_HOST:-0.0.0.0}" --port "${WEB_PORT:-8092}"
fi
EOF
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
