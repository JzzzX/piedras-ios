# Repository Guidelines

## 项目结构与模块组织
`piedras/` 是 SwiftUI iOS 客户端。应用启动与容器放在 `piedras/App`，功能页面放在 `piedras/Features`，状态管理放在 `piedras/Stores`，通用服务放在 `piedras/Services`，数据模型与持久化放在 `piedras/Data`，共享组件与工具放在 `piedras/Shared`。

`piedrasTests/` 存放 XCTest 单元测试，覆盖仓储、Store、Service 和部分界面展示逻辑；`piedrasUITests/` 覆盖录音、导航等关键流程。服务端代码在 `cloud/api/`（Next.js + Prisma）与 `cloud/asr-proxy/`（旧版 WebSocket 代理）。说明文档放在 `docs/`，辅助脚本放在 `scripts/`。

## 架构与核心约定
- **本地优先（Local First）**：会议、转写、笔记等数据在同步前应优先落到本地存储。
- **单设备优先（Single Device Primary）**：同步默认遵循“最后写入者胜（last-write-wins）”策略，避免引入未经验证的复杂合并逻辑。
- **视觉风格一致性**：涉及主题或视觉语言调整时，优先延续 `AppTheme.swift` 中既有的设计令牌与整体风格。
- **国际化**：不要在 View 中硬编码字符串，统一通过 `AppStrings.current.<key>` 管理文案。
- **状态管理边界**：高层业务操作优先通过 `MeetingStore` 协调；全局状态优先沿用现有 `@Environment` 接入方式。
- **持久化边界**：数据库读写尽量优先通过 `MeetingRepository` 等仓储层完成，避免在业务代码中直接散落 `ModelContext` 操作。

## 构建、测试与开发命令
构建 iOS App：
```sh
xcodebuild -project Piedras.xcodeproj -scheme piedras -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
运行单测与 UI 测试：
```sh
xcodebuild test -project Piedras.xcodeproj -scheme piedras -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
本地启动云端 API：
```sh
cd cloud/api && npm install && npm run dev
```
执行接近生产的 API 构建与启动：
```sh
cd cloud/api && npm run build && npm run start
```
常用 Prisma 操作：
```sh
cd cloud/api && npx prisma generate
cd cloud/api && npx prisma db push
```
验证 ASR 链路：
```sh
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav http://127.0.0.1:3000
```

## 代码风格与命名约定
Swift 使用 4 空格缩进，保持与现有 Xcode 格式一致；仓库当前未提交 `swiftformat` 或 `swiftlint` 配置。类型名使用 `UpperCamelCase`，属性和方法使用 `lowerCamelCase`，无障碍标识符应清晰可读，例如 `MeetingAskButton`。

新增代码应尽量放入现有最小职责模块。页面专属 UI 优先放在 `piedras/Features/<Area>/`；只有在跨页面复用时才提升到 `Shared/`。

## 测试约定
单元测试使用 XCTest，文件命名遵循 `<Subject>Tests.swift`。UI 测试只覆盖关键用户路径，并优先复用现有启动参数，如 `UITEST_ISOLATED_DEFAULTS`、`UITEST_IN_MEMORY`，保证结果稳定。

提交前至少运行与改动最相关的最小测试范围。若修改 `cloud/api/`，至少确保 `npm run build` 能通过。

不要把简单问题复杂化。对于轻量级 UI 调整、文案修改、样式微调这类低风险改动，优先保持速度与质量平衡，不要追加无意义的测试、重构或过度实现；避免为一个简单问题投入过长时间。

## 提交与 Pull Request 规范
提交信息使用 Conventional Commits，摘要使用中文，风格参考近期历史：`feat(ios): 优化单条笔记对话空状态`、`fix: 修复录音停止后音频文件未同步问题`。

每次提交只包含一个清晰的逻辑变更。不要提交构建产物、临时截图、`tmp-ui-test-*` 导出文件或个人 Xcode 配置。PR 需要说明用户可见影响，标明涉及目录如 `piedras/` 或 `cloud/api/`，关联 Issue，并为 UI 改动附上截图。

完成一次与本仓库代码、配置、脚本或文档直接相关的操作后，需主动询问用户是否需要执行 `git commit && git push`。只有在用户明确同意后才执行提交与推送；提交信息应参考当前仓库历史，使用中文 Conventional Commits 格式，例如 `feat(ios): 优化单条笔记对话空状态`、`fix(api): 修复会话创建失败`。

## 配置说明
默认以生产后端链路为准。若需切换后端，请通过 `PIEDRAS_BACKEND_BASE_URL` 等构建配置覆盖，不要在应用代码中硬编码本地地址。
