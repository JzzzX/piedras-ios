# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 提供在此代码库中工作的指导。

## 常用命令

### iOS App (piedras/)
- **构建 (Build)**: `xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator build`
- **清理 (Clean)**: `xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator clean`
- **运行全量测试 (Test All)**: `xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator test`
- **运行单个测试 (Test Single)**: `xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator test -only-testing:piedrasTests/<测试类名>/<测试方法名>`

### 云端 API (cloud/api/)
- **安装依赖**: `cd cloud/api && npm install`
- **构建**: `cd cloud/api && npm run build`
- **启动开发服务器**: `cd cloud/api && npm run dev`
- **启动生产服务器**: `cd cloud/api && npm run start`
- **Prisma 生成**: `cd cloud/api && npx prisma generate`
- **Prisma 推送**: `cd cloud/api && npx prisma db push`

### 诊断脚本 (Diagnostic Scripts)
- **ASR 冒烟测试**: `node scripts/asr_smoke_test.mjs <音频文件.wav> [后端地址]`
- **生成测试音频**:
  ```bash
  say -o tmp-asr-sample.aiff "你好，我在测试 Piedras 的实时转写能力。"
  afconvert -f WAVE -d LEI16 tmp-asr-sample.aiff tmp-asr-sample.wav
  ```

## 架构与结构

### 核心原则
- **本地优先 (Local First)**: 所有数据（会议、转写、笔记）在同步前均通过 SwiftData 存储在本地。
- **单设备为主 (Single Device Primary)**: 同步遵循“最后写入者胜 (last-write-wins)”策略，不进行复杂的合并。
- **复古美学**: 在 `AppTheme.swift` 中定义了特定的设计令牌，以实现经典的 Macintosh 视觉风格。

### 目录布局
- `piedras/`: iOS SwiftUI 应用程序。
  - `App/`: 生命周期 (`PiedrasApp`)、依赖注入 (`AppContainer`) 和路由 (`AppRouter`)。
  - `Data/`: SwiftData 模型 (`Meeting`, `TranscriptSegment`)、仓库 (Repository) 以及后端兼容适配器。
  - `Services/`: 领域逻辑，包括音频 (Audio)、ASR (WebSocket)、网络 (APIClient) 和同步 (Sync)。
  - `Stores/`: 使用 `@Observable` 的状态管理。`MeetingStore`（主要业务流程）和 `RecordingSessionStore`（实时录音状态）。
  - `Features/`: 按功能分组的 View 实现。`MeetingDetail` 是核心的“AI 笔记优先”界面。
  - `Shared/`: 用于样式的 `AppTheme` 和用于多语言（中/英）的 `AppStrings`。
- `cloud/api/`: 基于 Next.js 的后端，提供 LLM (OpenAI 兼容) 和 ASR (豆包) 集成。

### 编码标准
- **提交流程**: 在完成一次代码项目相关的操作（如功能实现、Bug 修复或重构）后，应主动询问用户是否需要进行 `git commit & push`。如果用户同意，请按照以下规范执行。
- **提交信息**: 使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范，并使用 **中文** 编写。
  - 格式: `<type>(scope): <中文说明>`
  - 示例: `feat(ios): 添加可折叠录音条`, `fix: 修复同步冲突`
  - 包含 `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` (或当前模型版本) 标识。
- **国际化 (Localization)**: 不要在 View 中硬编码字符串。使用 `AppStrings.current.<key>`。
- **状态管理**: 使用 `MeetingStore` 进行高层级操作。在 SwiftUI 视图中通过 `@Environment` 访问全局状态。
- **持久化**: 尽量优先使用 `MeetingRepository` 进行数据库操作，而非直接使用 `ModelContext`。
