# ScienceFictionCollection-Web 部署评估与指南

| 项目 | 内容 |
| --- | --- |
| 评估对象 | [dongf9527/ScienceFictionCollection-Web](https://github.com/dongf9527/ScienceFictionCollection-Web)（`main@c9340a0`，与上游同步的完整副本） |
| 配套内容仓库 | [dongf9527/ScienceFictionCollection](https://github.com/dongf9527/ScienceFictionCollection)（`main@22d3576`） |
| 评估目的 | 确定可行部署路径，给出可复制的部署步骤与命令行 |
| 评估日期 | 2026-10-31 |

---

## 1. 部署可行性评估

**结论：可部署性 5/5。** 该应用是 Next.js 16 的**纯静态导出**（`next.config.mjs` 中 `output: 'export'`），构建产物为自包含的 `out/` 目录（HTML + 静态资源 + `.nojekyll` + `build-info.json`），**运行期不需要任何服务端**，任何静态托管平台均可承载。构建链自带完整质量门：`pnpm test`（8 个测试文件）→ 构建 → `pnpm check:export`（逐页校验 canonical、资源前缀、sitemap，并强制断言**不打包小说正文**）。

### 四条硬约束（所有方案通用）

| # | 约束 | 依据 | 应对 |
| --- | --- | --- | --- |
| 1 | 构建环境钉死：Node `>=24.22 <25`、pnpm `9.15.2` | `.nvmrc` / `package.json#engines` / `scripts/check-runtime.mjs` 前置守卫，所有 npm script 执行前都会校验 | 用 `nvm install && nvm use`、`corepack` 或平台环境变量满足版本 |
| 2 | 构建前必须准备元数据 | `prepare-collection.mjs` 默认读兄弟目录 `../ScienceFictionCollection/metadata`，可用 `COLLECTION_METADATA_DIR` 覆盖 | 本地：双仓库兄弟目录；CI/云平台：先 sparse clone 内容仓库再指定 `COLLECTION_METADATA_DIR` |
| 3 | base path 机制 | `build-pages.mjs` 硬编码 `NEXT_PUBLIC_BASE_PATH=/ScienceFictionCollection-Web`，`finalize-export.mjs` 写入 `build-info.json`，`verify-static-export.mjs` 强制校验所有资源链接带此前缀 | GitHub Pages 项目站直接可用（dongf9527 仓库名与上游相同，**无需改动**）；根路径部署用 `pnpm build`（不设 base path） |
| 4 | 运行期正文按需加载 | `lib/site.ts` 的 `CONTENT_REPO_OWNER/NAME` + `lib/metadata.ts:144` 拼装 `raw.githubusercontent.com/.../master/<path>` | 部署本身无需处理；境内访问优化见 §5 |

### 部署方案对比

| 方案 | 工作量 | 成本 | CI 自动化 | 境内可达 | 适用场景 |
| --- | --- | --- | --- | --- | --- |
| **A. GitHub Pages + Actions**（推荐） | 低（改 1 个文件 + 开 1 个开关） | 免费 | ✅ 上游原生流水线 | 站点一般可达，正文依赖 raw（见 §5） | 默认选择，与上游设计完全一致 |
| B. 自托管 nginx / Docker | 中 | 服务器成本 | 自建（Webhook/定时） | ✅ 可控 | 内网/自有服务器、需要完全掌控 |
| C1. Vercel | 低-中 | 免费档可用 | ✅ 平台内置 | 站点可达性一般 | 想要预览部署与全球 CDN |
| C2. Cloudflare Pages | 低-中 | 免费档可用 | ✅ 平台内置 | ✅ 通常最好 | 境内访问优先级最高时 |

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

## 4. 方案 C：Vercel / Cloudflare Pages

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

## 5. 正文分发优化（部署后的首要议题）

部署后阅读器仍从 `raw.githubusercontent.com/VeejaLiu/ScienceFictionCollection/master/<path>` 按需加载正文。**境内访问该域名不稳定，会直接表现为"书打开是空的"**。三个选项：

| 选项 | 做法 | 改动点 | 评价 |
| --- | --- | --- | --- |
| **反代**（推荐） | Cloudflare Workers 反代 `raw.githubusercontent.com`，绑定自定义域 | `lib/metadata.ts:144` 的 URL 前缀改一处 | 改动最小、零存储成本 |
| 对象存储 | CI 把正文同步到 R2/OSS，阅读器从 CDN 取 | 同上，一处 URL；另加一条同步流水线 | 可控性最强，略有存储/流量成本 |
| 构建期打包 | 把正文打进 `out/` | ⚠️ 与 `verify-static-export.mjs:45` "collection/ 下禁止 txt/epub" 断言冲突，需同步改校验与 CI | 体积 +60MB，偏离上游设计，不推荐 |

> 注意：若正文仅切到 `dongf9527/ScienceFictionCollection`（同在 GitHub），只消除"仓库作者"差异，**不解决**境内可达性——仍需本节的反代/存储方案。

---

## 6. 排错清单

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| 任何脚本报"需要 Node.js >=24.22" | 版本守卫 | `nvm install && nvm use`；容器内用 `node:24-alpine` |
| 报"请使用 pnpm@9.15.2" | 包管理器守卫 | `npm i -g pnpm@9.15.2` 或 `corepack enable` |
| `prepare-collection` 报找不到 metadata | 兄弟目录不存在 | `export COLLECTION_METADATA_DIR=/绝对路径/ScienceFictionCollection/metadata` |
| `check:export` 失败：missing Pages prefix | 用了裸 `pnpm build` 但按项目站部署 | 项目站部署必须 `pnpm build:pages`；根路径部署才用 `pnpm build` |
| Pages 打开 404 / 资源 404 | base path 与实际子路径不一致 | 确认仓库名为 `ScienceFictionCollection-Web`（base path 硬编码与之绑定）；改名需同步改 `build-pages.mjs` |
| push 提示 refusing to allow ... workflow | token 缺 Workflows 权限 | fine-grained token 勾选 Workflows 读写 |
| 书能打开但正文空白 | `raw.githubusercontent.com` 不可达，或 `CONTENT_REPO_*` 指向的仓库/分支无该文件 | 浏览器 DevTools 看具体失败 URL；按 §5 优化或核对 `lib/site.ts` |
| `check:export` 报 novel body bundled | 误把正文拷进了 `public/collection/` | 恢复 `prepare-collection.mjs` 原逻辑（只复制 JSON 与图片） |

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
```

> 本文档基于 `main@c9340a0` 快照撰写；§2 的 A1 sed 改造为**指导步骤**，尚未在仓库中执行——如需代为执行并触发部署，请确认。
