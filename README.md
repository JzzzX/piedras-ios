# Piedras iOS

Piedras iOS 是一个聚焦录音、实时转写、纯文本笔记与单会议 AI 总结/问答的原生 iOS App。

当前仓库同时承载：

- `piedras/`：iOS SwiftUI 客户端
- `cloud/api/`：iOS 依赖的 Next.js 云端 API，也是当前推荐的统一云端入口
- `cloud/asr-proxy/`：旧的独立豆包实时识别代理，保留用于兼容和单独调试

仓库现已切换为单主仓模式，不再以外部后端仓库作为长期依赖前提。

## 默认运行方式

- App 默认连接生产云后端；默认值可通过构建配置 `PIEDRAS_BACKEND_BASE_URL` 注入
- LLM 走 AiHubMix 的 OpenAI-compatible 后端
- ASR 走豆包实时识别，由统一 Zeabur 服务签发 session 并承载 WebSocket 代理
- 普通用户路径不再依赖本地 `localhost` 或局域网地址配置

## 仓库结构

```text
piedras-ios/
  piedras/            # iOS App
  cloud/api/          # 推荐部署到 Zeabur 的单入口 API + ASR 代理
  cloud/asr-proxy/    # 兼容旧部署的独立代理
  docs/
  scripts/
```

## 文档

- 详细方案见 [docs/piedras-ios-mvp-plan.md](docs/piedras-ios-mvp-plan.md)
- 部署说明见 [docs/cloud-deployment.md](docs/cloud-deployment.md)
- `cloud/api` 部署说明见 [cloud/api/README.md](cloud/api/README.md)
- 提交规范见 [CONTRIBUTING.md](CONTRIBUTING.md)

## 联调

真实 ASR 链路可通过冒烟脚本验证。默认会请求云端 API；若要联调本地后端，可额外传入本地地址：

```text
say -o tmp-asr-sample.aiff "你好，我在测试 Piedras 的实时转写能力。"
afconvert -f WAVE -d LEI16 tmp-asr-sample.aiff tmp-asr-sample.wav
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav http://127.0.0.1:3000
```

脚本会自动请求 `/api/asr/session`、连接豆包 ASR 代理、按 200ms 发送 PCM，并打印 `partial` / `final` 结果。

本地模拟生产统一入口时，可使用：

```text
cd cloud/api && npm install && npx prisma generate && npm run build && npm run start
```

如果只是单独调试旧版独立代理，再使用：

```text
cd cloud/asr-proxy && npm install && npm start
```

## 提交信息规范

本仓库采用 Conventional Commits，提交说明使用中文。

示例：

```text
feat: 完成会议列表和本地搜索
fix: 修复录音停止后音频文件未同步问题
docs: 更新 iOS MVP 架构计划
```
