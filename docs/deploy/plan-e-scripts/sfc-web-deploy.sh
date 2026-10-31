#!/usr/bin/env bash
# sfc-web-deploy.sh —— 方案 E 部署脚本：拉取代码 → 构建 → 校验 → 发布到 nginx 目录
# 用法: sfc-web-deploy.sh          （通常通过 sfc-web.sh deploy 调用）
# 环境变量（均可选）:
#   SFC_ROOT    两仓库所在父目录，默认 /opt/sfc
#   WEB_ROOT    nginx 站点根目录，默认 /var/www/sfc-web/out
#   SITE_URL    站点规范地址，默认 http://localhost:8080/（对外服务请改为实际局域网 IP 或域名）
set -euo pipefail

SFC_ROOT="${SFC_ROOT:-/opt/sfc}"
WEB_DIR="$SFC_ROOT/ScienceFictionCollection-Web"
COLL_DIR="$SFC_ROOT/ScienceFictionCollection"
WEB_ROOT="${WEB_ROOT:-/var/www/sfc-web/out}"
SITE_URL="${SITE_URL:-http://localhost:8080/}"
LOG_FILE="${LOG_FILE:-$SFC_ROOT/deploy.log}"

mkdir -p "$SFC_ROOT"
exec >> "$LOG_FILE" 2>&1
echo "==== [$(date '+%F %T')] 开始部署 SITE_URL=$SITE_URL ===="

# 1. 更新代码（两仓库必须同处一个父目录：构建期要读内容仓库的 metadata）
cd "$WEB_DIR"
git pull --ff-only origin main
git -C "$COLL_DIR" pull --ff-only origin main

# 2. Node 24 / pnpm 9.15.2（nvm 安装方式；若用 NodeSource apt 安装，删去下面三行即可）
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use 24

# 3. 质量门 + 构建（根路径版：无 basePath；构建期元数据指向内容仓库）
pnpm install --frozen-lockfile
export COLLECTION_METADATA_DIR="$COLL_DIR/metadata"
export SITE_URL
export NEXT_TELEMETRY_DISABLED=1
pnpm test
pnpm build
pnpm check:export

# 4. 发布（webroot 已 chown 给当前用户，rsync 无需 sudo）
mkdir -p "$WEB_ROOT"
rsync -av --delete out/ "$WEB_ROOT"/

# 5. 生效（WSL 默认用户 sudo 免密；systemd 随 WSL 启动）
sudo nginx -t && sudo systemctl reload nginx
echo "==== [$(date '+%F %T')] 部署完成：$SITE_URL ===="
