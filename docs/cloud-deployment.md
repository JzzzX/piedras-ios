# Piedras 单入口 Zeabur 部署

## 目标

当前生产目标只有一条：

- 不再让 iOS 走 `Vercel API + Zeabur ASR` 的混合链路
- 统一改成一个 Zeabur 阿里云服务同时承载 `cloud/api` 和豆包 ASR WebSocket 代理
- 保持现有 AiHubMix / AliHub 的 OpenAI-compatible LLM 配置，不做 provider 迁移

## 推荐拓扑

现有 Zeabur 域名直接作为唯一入口：

```text
https://piedras.preview.aliyun-zeabur.cn
```

这个服务应当由仓库根目录的 `Dockerfile.asr-proxy` 构建，但实际运行的是 `cloud/api/server.cjs`，因此同一个端口会同时提供：

- `GET /healthz`
- `GET /api/asr/status`
- `GET /api/llm/status`
- `POST /api/asr/session`
- `GET /asr-proxy/healthz`
- `WS /ws/asr`

## Zeabur 配置

### 部署入口

如果当前 Zeabur 服务已经绑定仓库根目录，保持不动即可，并确认：

```bash
ZBPACK_DOCKERFILE_NAME=asr-proxy
```

这会让 Zeabur 使用仓库根目录的 `Dockerfile.asr-proxy`，把现有服务升级为单入口 API + ASR 代理。

如果你新建 Zeabur 服务，也可以直接把 Root Directory 指向：

```text
cloud/api
```

然后使用 `cloud/api/Dockerfile`。

### 构建与启动

- Node 版本：20
- 推荐直接使用仓库内 Dockerfile，不要手写平台构建命令
- 不要手动设置 `PORT`
- 平台会自动注入 `PORT`

### 必需环境变量

以下变量需要在同一个 Zeabur 服务内同时存在：

```bash
DATABASE_URL=
ADMIN_API_SECRET=
ASR_MODE=doubao

AIHUBMIX_API_KEY=
AIHUBMIX_BASE_URL=https://aihubmix.com/v1
AIHUBMIX_MODEL=gemini-3-flash-preview
AIHUBMIX_PATH=/chat/completions
LLM_PROVIDER=aihubmix

ASR_PROXY_SESSION_SECRET=
ASR_PROXY_PUBLIC_BASE_URL=https://piedras.preview.aliyun-zeabur.cn
ASR_PROXY_HEALTH_PATH=/asr-proxy/healthz
ASR_PROXY_WS_PATH=/ws/asr

DOUBAO_ASR_APP_ID=
DOUBAO_ASR_ACCESS_TOKEN=
DOUBAO_ASR_RESOURCE_ID=volc.seedasr.sauc.duration
LEGACY_BOOTSTRAP_PASSWORD=
```

可选变量：

```bash
DOUBAO_ASR_WS_URL=wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async
```

说明：

- 你现在提供的 Zeabur 环境变量里只有豆包凭据和 `ZBPACK_DOCKERFILE_NAME`
- 还必须补上 `DATABASE_URL`、`ADMIN_API_SECRET`、`ASR_MODE`、`ASR_PROXY_PUBLIC_BASE_URL`、`ASR_PROXY_HEALTH_PATH`、`ASR_PROXY_WS_PATH`，以及现有 `AIHUBMIX_*` 变量
- 建议显式设置 `LLM_PROVIDER=aihubmix`，把线上 LLM 路径固定到 AiHubMix，避免误配到历史 provider
- `ASR_PROXY_PUBLIC_BASE_URL` 必须写成实际公网域名，当前就是 `https://piedras.preview.aliyun-zeabur.cn`
- 如果现在线上数据库还是旧版共享数据结构，新增代码会在服务启动时自动补账号 schema
- 如果你希望旧数据自动挂到两个可登录测试账号，再补一个 `LEGACY_BOOTSTRAP_PASSWORD`；服务首次启动后会自动创建：
  - `legacy-main@piedras.local`
  - `legacy-archive@piedras.local`

## iOS 对应配置

- iOS 默认生产后端已经改成 `https://piedras.preview.aliyun-zeabur.cn`
- Debug 设置页支持手动覆盖后端地址，便于临时切服排障

## 上线后验证

统一入口部署成功后，下面这些请求都应该返回有效结果：

```bash
curl https://piedras.preview.aliyun-zeabur.cn/healthz
curl https://piedras.preview.aliyun-zeabur.cn/asr-proxy/healthz
curl https://piedras.preview.aliyun-zeabur.cn/api/asr/status
curl https://piedras.preview.aliyun-zeabur.cn/api/llm/status
curl -X POST https://piedras.preview.aliyun-zeabur.cn/api/asr/session \
  -H 'content-type: application/json' \
  -d '{"sampleRate":16000,"channels":1}'
```

如果仍然出现下面这种情况：

- `/healthz` 有返回
- `/api/asr/status` 是 `{"error":"Not found"}`

说明线上跑的还是旧的独立 `cloud/asr-proxy`，还没有完成新镜像部署。
