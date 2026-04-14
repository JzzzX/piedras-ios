# 椰子面试 iOS

椰子面试是一个面向面试场景的原生 iOS 录音与转写产品，当前聚焦录音、实时转写、笔记整理、AI 总结与问答闭环。

这个仓库是组织内单主仓，承载：

- `CocoInterview/`：SwiftUI iOS 客户端
- `cloud/api/`：Next.js + Prisma 云端 API
- `cloud/asr-proxy/`：独立部署时可复用的 ASR WebSocket 代理
- `docs/`：部署、交接与历史设计文档
- `scripts/`：冒烟验证与发布校验脚本

## 开发命令

构建 iOS App：

```sh
xcodebuild -project CocoInterview.xcodeproj -scheme CocoInterview -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

运行 iOS 测试：

```sh
xcodebuild test -project CocoInterview.xcodeproj -scheme CocoInterview -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

启动云端 API：

```sh
cd cloud/api && npm install && npm run dev
```

构建云端 API：

```sh
cd cloud/api && npm run build
```

验证 ASR 链路：

```sh
say -o tmp-asr-sample.aiff "你好，我在测试椰子面试的实时转写能力。"
afconvert -f WAVE -d LEI16 tmp-asr-sample.aiff tmp-asr-sample.wav
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav http://127.0.0.1:3000
```

## 配置约定

- iOS 默认后端配置键为 `COCO_INTERVIEW_BACKEND_BASE_URL`
- 冒烟脚本环境变量为 `COCO_INTERVIEW_BACKEND_URL`
- 当前仓库中的默认生产地址使用占位域名 `https://api.coco-interview.example.com`
- 在组织正式部署前，必须通过构建配置或环境变量替换为真实域名

## 文档

- 核心 MVP 设计见 [docs/coco-interview-ios-mvp-plan.md](docs/coco-interview-ios-mvp-plan.md)
- 部署说明见 [docs/cloud-deployment.md](docs/cloud-deployment.md)
- ASR / LLM 交接说明见 [docs/asr-llm-handoff.md](docs/asr-llm-handoff.md)
- `cloud/api` 说明见 [cloud/api/README.md](cloud/api/README.md)
- 提交规范见 [CONTRIBUTING.md](CONTRIBUTING.md)
