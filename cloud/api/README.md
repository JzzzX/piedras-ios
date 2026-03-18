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

- Vercel 项目 root 应指向 `cloud/api`
- 生产环境继续使用 PostgreSQL
- `ASR_PROXY_PUBLIC_BASE_URL` 应指向 `cloud/asr-proxy` 的公网地址
