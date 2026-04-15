# 椰子面试 iOS

椰子面试 is a personal iOS product for recording conversations, turning them into transcripts, and shaping them into usable notes with AI.

椰子面试是一个面向真实对话记录场景的个人 iOS 产品，重点放在录音、转写、笔记整理，以及基于上下文的 AI 辅助。

![椰子面试 Home](.github/assets/screenshots/01-home-feed.png)

## Product

### 中文

- 原生 iOS 录音与转写体验，围绕“打开即记”设计。
- 录音结束后可以继续整理笔记、查看转写、补充资料、生成 AI 笔记。
- 支持跨记录提问，把历史内容当作可检索的个人知识上下文。
- 当前仓库同时包含 iOS 客户端、云端 API，以及独立 ASR 代理。

### English

- Native iOS capture flow built for quick recording and note-taking.
- Review transcripts, organize notes, attach context, and generate AI-enhanced notes after recording.
- Ask questions across past sessions and reuse them as searchable personal context.
- This repo includes the iOS app, the cloud API, and a standalone ASR proxy.

## Screenshots

| Home | Detail |
| --- | --- |
| ![Home Feed](.github/assets/screenshots/01-home-feed.png) | ![Meeting Detail](.github/assets/screenshots/02-meeting-detail-ai-notes.png) |

| Transcript | Global Chat |
| --- | --- |
| ![Transcript Sheet](.github/assets/screenshots/03-transcript-sheet.png) | ![Global Chat](.github/assets/screenshots/04-global-chat.png) |

## Repository Layout

- `CocoInterview/`: SwiftUI iOS app
- `CocoInterviewRecordingWidget/`: recording widget / Live Activity target
- `CocoInterviewTests/`: XCTest unit tests
- `CocoInterviewUITests/`: UI flow tests
- `cloud/api/`: Next.js + Prisma API
- `cloud/asr-proxy/`: standalone ASR WebSocket proxy
- `scripts/`: release and smoke-test helpers

## Development

Build the iOS app:

```sh
xcodebuild -project CocoInterview.xcodeproj -scheme CocoInterview -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run iOS tests:

```sh
xcodebuild test -project CocoInterview.xcodeproj -scheme CocoInterview -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Start the cloud API:

```sh
cd cloud/api
npm install
npx prisma generate
npm run dev
```

Build the cloud API:

```sh
cd cloud/api
npm run build
```

Smoke-test the ASR chain:

```sh
say -o tmp-asr-sample.aiff "你好，我在测试椰子面试的实时转写能力。"
afconvert -f WAVE -d LEI16 tmp-asr-sample.aiff tmp-asr-sample.wav
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav http://127.0.0.1:3000
```

## Configuration

- The iOS app reads the backend base URL from `COCO_INTERVIEW_BACKEND_BASE_URL`.
- The ASR smoke test reads the backend base URL from `COCO_INTERVIEW_BACKEND_URL`.
- This public repo does not ship with a production backend URL baked in. Provide one explicitly through build settings or environment variables.

## Status

椰子面试 is an actively maintained personal project. The product surface is intentionally opinionated and still evolving, but the repo is kept in a buildable, inspectable state so it can serve both as a working app and as a public engineering artifact.
