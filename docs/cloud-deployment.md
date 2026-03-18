# Piedras 单主仓云端部署

## 目标

本仓库同时承载 iOS 客户端和云端服务，部署时不要再把整个仓库当成单一 Node 项目。

固定拆分如下：

- Vercel: `cloud/api`
- Zeabur: `cloud/asr-proxy`

## Vercel

### 项目 Root Directory

设置为：

```text
cloud/api
```

### 必需环境变量

```bash
DATABASE_URL=
ASR_MODE=doubao
OPENAI_API_KEY=
OPENAI_BASE_URL=https://aihubmix.com/v1
OPENAI_MODEL=gpt-4o-mini
OPENAI_PATH=/chat/completions
DOUBAO_ASR_APP_ID=
DOUBAO_ASR_ACCESS_TOKEN=
DOUBAO_ASR_RESOURCE_ID=volc.seedasr.sauc.duration
ASR_PROXY_SESSION_SECRET=
ASR_PROXY_PUBLIC_BASE_URL=https://your-asr-proxy.example.com
```

### 域名

- 正式 API 域名继续使用 `https://piedras-api.vercel.app`

## Zeabur

### 服务 Root Directory

设置为：

```text
cloud/asr-proxy
```

### 环境变量

```bash
ASR_PROXY_SESSION_SECRET=
DOUBAO_ASR_APP_ID=
DOUBAO_ASR_ACCESS_TOKEN=
DOUBAO_ASR_RESOURCE_ID=volc.seedasr.sauc.duration
```

说明：

- 不要手动设置 `PORT`
- 平台会自动注入 `PORT`
- 代理代码会优先监听平台注入的 `PORT`

### 验证

代理上线后先测：

```bash
curl https://your-asr-proxy.example.com/healthz
```

然后再测 API：

```bash
curl https://piedras-api.vercel.app/api/asr/status
curl https://piedras-api.vercel.app/api/llm/status
```
