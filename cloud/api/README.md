# Piedras Cloud API

这是 `piedras-ios` 单主仓中的云端 API 子应用。

## 作用

- 为 iOS 签发豆包 ASR session
- 提供会议 CRUD 与音频上传
- 提供 AI 标题、AI 增强笔记、会议内问答、全局问答
- 对外暴露健康检查和状态页

## 本地运行

```bash
npm install
npx prisma generate
npm run dev
```

默认访问：

- `/`
- `/healthz`
- `/api/llm/status`
- `/api/asr/status`

## 部署

- 推荐使用单入口 Zeabur 部署：同一个服务同时承载 `cloud/api + ASR proxy`
- 若沿用当前仓库根目录绑定的 Zeabur 服务，设置 `ZBPACK_DOCKERFILE_NAME=asr-proxy`
- 若新建 Zeabur 服务，也可以把 root 指向 `cloud/api`
- 生产环境继续使用 PostgreSQL
- `ASR_PROXY_PUBLIC_BASE_URL` 应指向当前公网域名
- 如使用一体化入口，建议同时设置 `ASR_PROXY_HEALTH_PATH=/asr-proxy/healthz`
- 一体化入口默认 WebSocket 路径为 `ASR_PROXY_WS_PATH=/ws/asr`
