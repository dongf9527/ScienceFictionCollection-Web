# ScienceFictionCollection-Web 部署评估与指南

| 项目 | 内容 |
| --- | --- |
| 评估对象 | [dongf9527/ScienceFictionCollection-Web](https://github.com/dongf9527/ScienceFictionCollection-Web)（`main@c9340a0`，与上游同步的完整副本） |
| 配套内容仓库 | [dongf9527/ScienceFictionCollection](https://github.com/dongf9527/ScienceFictionCollection)（`main@22d3576`） |
| 评估目的 | 确定可行部署路径，给出可复制的部署步骤与命令行 |
| 评估日期 | 2026-10-31 |
| 修订记录 | 2026-10-31 增补方案 E：GPU 服务器 · WSL · nginx 直装（无 Docker），含环境部署 / 依赖安装 / 服务启停脚本 |

---

## 1. 部署可行性评估

**结论：可部署性 5/5。** 该应用是 Next.js 16 的**纯静态导出**（`next.config.mjs` 中 `output: 'export'`），构建产物为自包含的 `out/` 目录（HTML + 静态资源 + `.nojekyll` + `build-info.json`），**运行期不需要任何服务端**，任何静态托管平台均可承载。构建链自带完整质量门：`pnpm test`（8 个测试文件）→ 构建 → `pnpm check:export`（逐页校验 canonical、资源前缀、sitemap，并强制断言**不打包小说正文**）。

### 四条硬约束（所有方案通用）

| # | 约束 | 依据 | 应对 |
| --- | --- | --- | --- |
| 1 | 构建环境钉死：Node `>=24.22 <25`、pnpm `9.15.2` | `.nvmrc` / `package.json#engines` / `scripts/check-runtime.mjs` 前置守卫，所有 npm script 执行前都会校验 | 用 `nvm install && nvm use`、`corepack` 或平台环境变量满足版本 |
| 2 | 构建前必须准备元数据 | `prepare-collection.mjs` 默认读兄弟目录 `../ScienceFictionCollection/metadata`，可用 `COLLECTION_METADATA_DIR` 覆盖 | 本地：双仓库兄弟目录；CI/云平台：先 sparse clone 内容仓库再指定 `COLLECTION_METADATA_DIR` |
| 3 | base path 机制 | `build-pages.mjs` 硬编码 `NEXT_PUBLIC_BASE_PATH=/ScienceFictionCollection-Web`，`finalize-export.mjs` 写入 `build-info.json`，`verify-static-export.mjs` 强制校验所有资源链接带此前缀 | GitHub Pages 项目站直接可用（dongf9527 仓库名与上游相同，**无需改动**）；根路径部署用 `pnpm build`（不设 base path） |
| 4 | 运行期正文按需加载 | `lib/site.ts` 的 `CONTENT_REPO_OWNER/NAME` + `lib/metadata.ts:144` 拼装 `raw.githubusercontent.com/.../master/<path>` | 部署本身无需处理；境内访问优化见 §6 |

### 部署方案对比

| 方案 | 工作量 | 成本 | CI 自动化 | 境内可达 | 适用场景 |
| --- | --- | --- | --- | --- | --- |
| **A. GitHub Pages + Actions**（推荐） | 低（改 1 个文件 + 开 1 个开关） | 免费 | ✅ 上游原生流水线 | 站点一般可达，正文依赖 raw（见 §6） | 默认选择，与上游设计完全一致 |
| B. 自托管 nginx / Docker | 中 | 服务器成本 | 自建（Webhook/定时） | ✅ 可控 | 内网/自有服务器、需要完全掌控 |
| C1. Vercel | 低-中 | 免费档可用 | ✅ 平台内置 | 站点可达性一般 | 想要预览部署与全球 CDN |
| C2. Cloudflare Pages | 低-中 | 免费档可用 | ✅ 平台内置 | ✅ 通常最好 | 境内访问优先级最高时 |
| **E. 自托管 nginx（GPU 服务器 · WSL，无 Docker）** | 中（环境一次性装好，脚本化后一键） | 零新增（复用已有 GPU 服务器） | 脚本 + WSL 开机自启 | ✅ 内网完全可控 | 阅读站与训练/计算任务同机共存 |

---

## 2. 方案 A：GitHub Pages + Actions（推荐）

### A0 前提

- 本地已 clone 两仓库并放同一父目录（构建期元数据依赖）：
  ```bash
  mkdir -p ~/sfc && cd ~/sfc
  git clone https://github.com/dongf9527/ScienceFictionCollection.git
  git clone https://github.com/dongf9527/ScienceFictionCollection-Web.git
  cd ScienceFictionCollection-Web
  nvm install && nvm use                 # Node 24.22（.nvmrc）
  npm install -g pnpm@9.15.2             # 或 corepack enable
  pnpm install --frozen-lockfile
  ```

### A1 一次性改造：把部署与内容源指向 dongf9527

上游工作流有 4 处指向 VeejaLiu，需要修改（`.github/workflows/pages.yml`）：

```bash
cd ScienceFictionCollection-Web

# ① 触发分支：master → main
sed -i 's|branches: \[master\]|branches: [main]|' .github/workflows/pages.yml
# ② 内容仓库：VeejaLiu → dongf9527（CI 里 sparse-checkout metadata 的来源）
sed -i 's|repository: VeejaLiu/ScienceFictionCollection|repository: dongf9527/ScienceFictionCollection|' .github/workflows/pages.yml
# ③ 内容分支默认值：'master' → 'main'（全文件唯一一处带引号的 'master'）
sed -i "s/'master'/'main'/" .github/workflows/pages.yml
# ④ 站点 URL：换成自己的 GitHub Pages 域名
sed -i 's|veejaliu.github.io|dongf9527.github.io|g' .github/workflows/pages.yml .env.example scripts/build-pages.mjs

# ⑤（可选，切正文来源为自有仓库）阅读器运行时取正文的仓库常量
sed -i "s|CONTENT_REPO_OWNER = 'VeejaLiu'|CONTENT_REPO_OWNER = 'dongf9527'|" lib/site.ts

# 检查改动
git diff
git add -A && git commit -m "chore(web): point pages deployment and content source at dongf9527"
git push origin main
```

> ⚠️ 该提交修改了 workflow 文件：fine-grained token 需要 **Workflows 读写权限**；若 push 被拒（提示 refusing to allow ... workflow），到 token 设置中勾选该权限后重试。

### A2 启用 Pages（Source = GitHub Actions，一次性）

```bash
# 方式一：gh CLI
gh api repos/dongf9527/ScienceFictionCollection-Web/pages -X POST -f build_type=workflow

# 方式二：纯 curl（TOKEN 换成具有该仓库 Administration 权限的 token）
curl -X POST \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/dongf9527/ScienceFictionCollection-Web/pages \
  -d '{"build_type":"workflow"}'
# 返回 201 成功；409 表示已启用
```

也可在网页操作：**Settings → Pages → Build and deployment → Source: GitHub Actions**。

### A3 触发构建并验证

```bash
# 手动触发（push 到 main 也会自动触发，前提 A1 已推送）
curl -X POST \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/dongf9527/ScienceFictionCollection-Web/actions/workflows/pages.yml/dispatches \
  -d '{"ref":"main"}'

# 观察运行状态（或网页 Actions 页）
gh run watch

# 完成后验证
curl -s -o /dev/null -w "%{http_code}\n" \
  https://dongf9527.github.io/ScienceFictionCollection-Web/
```

站点地址：`https://dongf9527.github.io/ScienceFictionCollection-Web/`

### A4 本地预演（推送前验证，强烈建议）

```bash
# 在 A0 的目录里执行
pnpm test                                            # 8 个单元测试
SITE_URL=https://dongf9527.github.io/ScienceFictionCollection-Web/ pnpm build:pages
pnpm check:export                                    # 逐页校验导出完整性
node scripts/serve-static.mjs --port 8080            # 本地预览（basePath 生效）
# 浏览器打开 http://127.0.0.1:8080/ScienceFictionCollection-Web/
```

---

## 3. 方案 B：自托管（nginx / Docker）

> 本节含 nginx 裸配（B1–B2）与 Docker 镜像（B3）两条路线。若目标机器是 **GPU 服务器 + WSL** 且**不使用 Docker**，直接使用 §4 的方案 E（含环境部署、依赖安装与服务启停脚本）。

### B1 构建静态产物（根路径域名部署）

```bash
cd ScienceFictionCollection-Web
# 元数据来源：指向内容仓库的 metadata（本机已有兄弟目录则可省略 COLLECTION_METADATA_DIR）
export COLLECTION_METADATA_DIR="$PWD/../ScienceFictionCollection/metadata"
export SITE_URL="https://books.example.com/"     # 换成实际域名
pnpm test && pnpm build && pnpm check:export
# 产物在 out/（根路径版：无 basePath 前缀）
```

### B2 nginx 配置（`trailingSlash: true`，每个路由是"目录/index.html"）

```nginx
server {
    listen 80;
    server_name books.example.com;
    root /var/www/sfc-web/out;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
    location ~* \.(webp|png|jpe?g|svg|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml text/xml application/xml;
}
```

```bash
sudo rsync -av --delete out/ /var/www/sfc-web/out/
sudo nginx -t && sudo systemctl reload nginx
```

### B3 Docker 多阶段构建（可复制的完整示例）

`Dockerfile`：

```dockerfile
FROM node:24-alpine AS build
RUN apk add --no-cache git && corepack enable
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
# 构建期内拉取内容仓库元数据（仅 metadata，不含正文）
RUN git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/dongf9527/ScienceFictionCollection.git /collection \
 && git -C /collection sparse-checkout set metadata
ENV COLLECTION_METADATA_DIR=/collection/metadata \
    SITE_URL=https://books.example.com/ \
    NEXT_TELEMETRY_DISABLED=1
RUN pnpm test && pnpm build && pnpm check:export

FROM nginx:alpine
COPY --from=build /app/out /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

```bash
docker build -t sfc-web .
docker run -d --name sfc-web -p 8080:80 sfc-web
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/
```

---

## 4. 方案 E：自托管（GPU 服务器 · WSL · nginx 直装，无 Docker）

面向已有 Windows GPU 服务器的场景：不引入 Docker，在 **WSL2（Ubuntu 24.04）内直装 nginx 并常驻后台**，阅读站与训练/计算任务同机共存。整体链路：

```text
浏览器 ──http://<Windows主机IP>:8080/──▶ Windows（GPU 宿主）
                                          └─ WSL2 Ubuntu 24.04
                                             ├─ nginx :8080（systemd 常驻，服务静态文件）
                                             └─ /opt/sfc/ 双仓库 → pnpm build → out/ → rsync 发布
```

### E0 适用说明

- 纯静态站点 = 轻负载：nginx 常驻内存约 10–20 MB、**零 GPU 占用**、磁盘约 60 MB（`out/`），与训练/推理进程无资源冲突；`pnpm build` 峰值内存约 1–2 GB，建议避开训练高峰执行部署。
- 端口选 **8080**：避开 Windows 侧常被占用的 80，WSL 内监听也无需特权；想换端口，把下文 8080 全量替换即可。
- 阅读器运行期仍从 GitHub raw 按需拉正文（境内优化见 §6，其余排错见 §7）。

### E1 环境部署（Windows 侧，一次性，管理员 PowerShell）

```powershell
wsl --install -d Ubuntu-24.04        # 安装 WSL2 + Ubuntu 24.04，完成后重启
wsl --update && wsl --version        # 确认 WSL ≥ 2.0（支持 systemd 与镜像网络）
```

（推荐）启用**镜像网络**：局域网设备直接访问 `http://<Windows主机IP>:8080/`，免去端口转发。新建 `%USERPROFILE%\.wslconfig`：

```ini
[wsl2]
networkingMode=mirrored
```

> 镜像网络要求 Windows 11 22H2+（或 Server 2025）且 WSL ≥ 2.0；不满足则跳过，改用 E6 的 portproxy。

随后在 WSL 内启用 **systemd**（服务自启的前提），写入 `/etc/wsl.conf`：

```ini
[boot]
systemd=true
```

回到 PowerShell 执行 `wsl --shutdown`，重新进入 WSL 后验证：

```bash
ps -p 1 -o comm=                     # 应输出 systemd
```

### E2 安装依赖（WSL 侧，一次性）

```bash
sudo apt update && sudo apt install -y git nginx rsync curl ca-certificates

# Node 24：nvm 安装，与仓库 .nvmrc 对齐（满足 engines: >=24.22 <25）
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm" && \. "$NVM_DIR/nvm.sh"
nvm install 24 && node -v            # v24.x

npm i -g pnpm@9.15.2 && pnpm -v      # 9.15.2，check-runtime 前置守卫会校验

# 目录规划：/opt/sfc 放双仓库（兄弟目录约定），/var/www/sfc-web 为发布根
sudo mkdir -p /opt/sfc /var/www/sfc-web && sudo chown -R "$USER": /opt/sfc /var/www/sfc-web
cd /opt/sfc
git clone https://github.com/dongf9527/ScienceFictionCollection.git
git clone https://github.com/dongf9527/ScienceFictionCollection-Web.git
```

### E3 构建与发布脚本 `/opt/sfc/bin/sfc-web-deploy.sh`

职责：双仓库更新 → `pnpm install --frozen-lockfile` → 质量门（`pnpm test`）→ `pnpm build`（根路径版）→ `pnpm check:export` → rsync 发布 → `nginx -t` + reload；日志写 `/opt/sfc/deploy.log`。

```bash
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
```

保存后执行 `chmod +x /opt/sfc/bin/sfc-web-deploy.sh`。首次运行前确认 E2 已完成；之后每次内容更新只需重跑本脚本。

### E4 nginx 站点配置 `/etc/nginx/sites-available/sfc-web`

```nginx
# 方案 E 静态站点（WSL 内 nginx，直装无 Docker）
server {
    listen 8080;
    listen [::]:8080;
    server_name _;
    root /var/www/sfc-web/out;
    index index.html;

    # next.config.mjs trailingSlash: true —— 每个路由是"目录/index.html"
    location / {
        try_files $uri $uri/ =404;
    }

    # 带指纹的静态资源长缓存
    location ~* \.(webp|png|jpe?g|svg|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml text/xml application/xml;
}
```

```bash
sudo ln -sf /etc/nginx/sites-available/sfc-web /etc/nginx/sites-enabled/sfc-web
sudo rm -f /etc/nginx/sites-enabled/default      # 防止默认站点抢占
sudo nginx -t && sudo systemctl enable --now nginx
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/   # 输出 200 即就绪
```

### E5 后台服务启停脚本 `/opt/sfc/bin/sfc-web.sh`

站点是纯静态文件，**nginx 即服务本体**：`start/stop/restart` 管 nginx 生命周期，`deploy` 一键重建发布，`logs` 聚合三类日志。

```bash
#!/usr/bin/env bash
# sfc-web.sh —— 方案 E 服务管理脚本（nginx 后台服务的启动/关闭/状态/部署/日志）
# 用法: sfc-web.sh {start|stop|restart|reload|enable|disable|status|deploy|logs}
#   start/stop/restart  启动、停止、重启 nginx（站点本身是纯静态文件，nginx 即服务本体）
#   enable/disable      设置/取消 WSL 启动时自动运行（systemd 自启）
#   status              查看运行状态
#   deploy              拉取代码并重新构建发布（调用同目录 sfc-web-deploy.sh）
#   logs                跟踪访问/错误/部署日志
set -euo pipefail

ACTION="${1:-status}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SFC_ROOT="${SFC_ROOT:-/opt/sfc}"

case "$ACTION" in
  start)   sudo systemctl start nginx ;;
  stop)    sudo systemctl stop nginx ;;
  restart) sudo systemctl restart nginx ;;
  reload)  sudo systemctl reload nginx ;;
  enable)  sudo systemctl enable nginx ;;      # WSL 启动时自动拉起
  disable) sudo systemctl disable nginx ;;
  status)  systemctl status nginx --no-pager -l ;;
  deploy)  exec "$SCRIPT_DIR/sfc-web-deploy.sh" ;;
  logs)    sudo tail -n 50 -f /var/log/nginx/access.log \
                    /var/log/nginx/error.log \
                    "$SFC_ROOT/deploy.log" ;;
  *) echo "用法: $0 {start|stop|restart|reload|enable|disable|status|deploy|logs}"; exit 1 ;;
esac
```

```bash
chmod +x /opt/sfc/bin/sfc-web.sh
sudo ln -sf /opt/sfc/bin/sfc-web.sh /usr/local/bin/sfc-web
sfc-web enable && sfc-web start       # 设为 WSL 自启并立即启动
```

> 若未启用 systemd：以 `sudo service nginx start|stop` 管理进程，并在 `/etc/wsl.conf` 的 `[boot]` 段加 `command = service nginx start` 实现自启；建议按 E1 启用 systemd，与生产 Linux 行为一致。

### E6 Windows 侧：开机自启与局域网访问（管理员 PowerShell）

```powershell
# ① 登录时自动启动 WSL（systemd 随之拉起已 enable 的 nginx）
schtasks /Create /TN "SFC-WSL-Boot" /TR "wsl.exe -d Ubuntu-24.04 --exec true" /SC ONLOGON /RL HIGHEST /F

# ② 防火墙放行 8080（镜像网络 / NAT 模式都需要）
New-NetFirewallRule -DisplayName "SFC-Web 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow

# ③ 仅 NAT 模式（未配镜像网络）需要：端口转发到 WSL IP
$wslIp = (wsl -d Ubuntu-24.04 -- hostname -I).Trim().Split(' ')[0]
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=$wslIp
```

> ③ 的 portproxy 绑定 WSL IP，WSL 重启后可能失效，需重跑刷新——把 ②③ 固化为开机计划任务，或直接改用 E1 镜像网络一劳永逸。`/SC ONLOGON` 在用户登录时触发：服务器场景请保持自动登录，或保留一个常驻会话。

### E7 验证

```bash
sfc-web deploy          # 首次部署；此后每次内容更新同样只跑这一条
sfc-web status          # 期望: active (running)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/    # 期望: 200
```

- Windows 本机：`http://localhost:8080/`；局域网设备：`http://<Windows主机IP>:8080/`。
- 打开任意一本书确认正文可加载；异常时对照 §6（正文分发）与 §7（排错清单）。

---

## 5. 方案 C：Vercel / Cloudflare Pages

### C1 Vercel

| 设置项 | 值 |
| --- | --- |
| Framework Preset | Other |
| Build Command | 见下 |
| Output Directory | `out` |
| Install Command | `npm i -g pnpm@9.15.2 && pnpm install --frozen-lockfile` |
| Node.js Version | 项目设置中选 24.x（若平台尚无 24，先勿放宽本地钉版，评估后再定） |

Build Command（在平台构建环境内先拉元数据，再走标准构建；根路径无需 base path）：

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/dongf9527/ScienceFictionCollection.git /tmp/collection \
  && git -C /tmp/collection sparse-checkout set metadata \
  && COLLECTION_METADATA_DIR=/tmp/collection/metadata SITE_URL=https://<your-app>.vercel.app pnpm build
```

### C2 Cloudflare Pages

| 设置项 | 值 |
| --- | --- |
| Build command | 与 C1 相同（把 SITE_URL 换成 `https://<project>.pages.dev`） |
| Build output directory | `/out` |
| 环境变量 | `NODE_VERSION=24.22.0` |

---

## 6. 正文分发优化（部署后的首要议题）

部署后阅读器仍从 `raw.githubusercontent.com/VeejaLiu/ScienceFictionCollection/master/<path>` 按需加载正文。**境内访问该域名不稳定，会直接表现为"书打开是空的"**。三个选项：

| 选项 | 做法 | 改动点 | 评价 |
| --- | --- | --- | --- |
| **反代**（推荐） | Cloudflare Workers 反代 `raw.githubusercontent.com`，绑定自定义域 | `lib/metadata.ts:144` 的 URL 前缀改一处 | 改动最小、零存储成本 |
| 对象存储 | CI 把正文同步到 R2/OSS，阅读器从 CDN 取 | 同上，一处 URL；另加一条同步流水线 | 可控性最强，略有存储/流量成本 |
| 构建期打包 | 把正文打进 `out/` | ⚠️ 与 `verify-static-export.mjs:45` "collection/ 下禁止 txt/epub" 断言冲突，需同步改校验与 CI | 体积 +60MB，偏离上游设计，不推荐 |

> 注意：若正文仅切到 `dongf9527/ScienceFictionCollection`（同在 GitHub），只消除"仓库作者"差异，**不解决**境内可达性——仍需本节的反代/存储方案。

---

## 7. 排错清单

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| 任何脚本报"需要 Node.js >=24.22" | 版本守卫 | `nvm install && nvm use`；容器内用 `node:24-alpine` |
| 报"请使用 pnpm@9.15.2" | 包管理器守卫 | `npm i -g pnpm@9.15.2` 或 `corepack enable` |
| `prepare-collection` 报找不到 metadata | 兄弟目录不存在 | `export COLLECTION_METADATA_DIR=/绝对路径/ScienceFictionCollection/metadata` |
| `check:export` 失败：missing Pages prefix | 用了裸 `pnpm build` 但按项目站部署 | 项目站部署必须 `pnpm build:pages`；根路径部署才用 `pnpm build` |
| Pages 打开 404 / 资源 404 | base path 与实际子路径不一致 | 确认仓库名为 `ScienceFictionCollection-Web`（base path 硬编码与之绑定）；改名需同步改 `build-pages.mjs` |
| push 提示 refusing to allow ... workflow | token 缺 Workflows 权限 | fine-grained token 勾选 Workflows 读写 |
| 书能打开但正文空白 | `raw.githubusercontent.com` 不可达，或 `CONTENT_REPO_*` 指向的仓库/分支无该文件 | 浏览器 DevTools 看具体失败 URL；按 §6 优化或核对 `lib/site.ts` |
| `check:export` 报 novel body bundled | 误把正文拷进了 `public/collection/` | 恢复 `prepare-collection.mjs` 原逻辑（只复制 JSON 与图片） |
| WSL 内 curl 200、局域网设备打不开 | NAT 模式未配 portproxy，或 Windows 防火墙未放行 8080 | 按 §4 E6 处理；或改用镜像网络 |
| Windows 重启后站点拒连 | WSL 未随登录启动（计划任务缺失），或 portproxy 指向的 WSL IP 已变 | 检查计划任务 SFC-WSL-Boot；重跑 E6 ③ 或换镜像网络 |
| 长时间睡眠后 git/https 报时间错误 | WSL 时钟漂移 | `sudo hwclock -s`，或 `wsl --shutdown` 后重进 |

---

## 附：命令速查

```bash
# 本地开发
pnpm dev                       # http://localhost:3014（自动 prepare-collection）
# 质量门
pnpm test && pnpm typecheck && pnpm lint
# GitHub Pages 构建（项目站）
SITE_URL=https://dongf9527.github.io/ScienceFictionCollection-Web/ pnpm build:pages && pnpm check:export
# 根路径构建（自托管/Vercel/CF）
COLLECTION_METADATA_DIR=... pnpm build
# 本地预览静态产物
node scripts/serve-static.mjs --port 8080
# 方案 E：WSL 自托管（GPU 服务器，详见 §4）
sfc-web deploy                                  # 构建并发布
sfc-web {start|stop|restart|status|logs}        # nginx 服务管理
```

> 本文档基于 `main@c9340a0` 快照撰写；§2 的 A1 sed 改造为**指导步骤**，尚未在仓库中执行——如需代为执行并触发部署，请确认。方案 E 的命令与脚本按 WSL2 + Ubuntu 24.04 标准路径编写，尚未在实机验证；落地时如有出入请反馈修订。
