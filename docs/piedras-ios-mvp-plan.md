# Piedras iOS 核心 MVP 重构计划

## 1. 项目目标

Piedras 现有 Web 端已经具备录音、转写、AI 总结、工作区、知识库、面试追踪、MCP 等较完整能力，但 iOS 首发版本不追求功能对齐，而是聚焦一个可以快速上线、真实可用、容易持续迭代的录音笔记核心产品。

本次 iOS MVP 的目标是：

- 以原生 `Swift + SwiftUI` 构建一个独立的 iOS App。
- 以本地录音、本地存储、本地可编辑笔记为主，保证离线可用。
- 复用现有 `ai_notepad` 的 Next.js 后端，避免重写服务端。
- 复用现有阿里云实时 ASR 协议和现有 LLM 后端能力。
- 严格控制范围，只保留最关键的录音笔记闭环。

## 2. MVP 范围

### 2.1 保留能力

- 会议列表
- 新建会议
- 麦克风录音
- 本地音频文件保存
- 前台实时转写
- 简洁文本笔记编辑
- 单会议 AI 总结
- 单会议 AI 对话
- 基本搜索
- 基本删除
- 音频播放与转写定位
- 后台持续录音

### 2.2 明确砍掉

- Workspace / Collection 层级
- 面试模式与候选人跟踪
- 知识库 / Asset 管理
- 全局跨会议问答
- Recipe / Template 管理 UI
- MCP 集成
- DOCX / Markdown 导出
- Webhook 分享
- 系统音频双轨
- 上传音频文件转写
- 前端 LLM Provider 切换
- 自定义 ASR 词表管理

## 3. 核心产品原则

### 3.1 本地优先

- 会议、转写段落、聊天记录、用户笔记全部先落本地。
- 网络只负责同步与 AI / ASR 能力调用。
- 不让网络成功成为用户录音和记录的前置条件。

### 3.2 单设备优先

- 先按照单设备使用场景设计。
- 同步策略采用 `last-write-wins`。
- 不做段落级冲突合并。
- 不做多端实时协作。

### 3.3 极简信息架构

- 首页只展示会议列表和新录音入口。
- 详情页只展示 `Notes / Transcript / AI` 三个核心区域。
- 所有复杂概念从 iOS UI 中移除。

### 3.4 后台能力边界清晰

- 后台继续录音。
- 后台不持续 WebSocket 实时转写。
- 回到前台后恢复后续转写，不回补后台空窗部分。

## 4. 技术架构

### 4.1 客户端技术栈

- `Swift`
- `SwiftUI`
- `SwiftData`
- `Observation`
- `URLSession`
- `AVFoundation`

### 4.2 服务端复用

iOS 继续复用现有 `ai_notepad` 后端：

- `POST /api/asr/session`
- `GET /api/asr/status`
- `GET /api/workspaces`
- `POST /api/workspaces`
- `GET /api/meetings`
- `GET /api/meetings/[id]`
- `POST /api/meetings`
- `DELETE /api/meetings/[id]`
- `POST /api/meetings/[id]/audio`
- `GET /api/meetings/[id]/audio`
- `POST /api/meetings/title`
- `POST /api/enhance`
- `POST /api/chat`

### 4.3 总体分层

- `App`：App 生命周期、依赖注入、路由
- `Data`：SwiftData 模型、Repository、适配器
- `Services`：音频、ASR、网络、同步
- `Stores`：界面状态与业务编排
- `Features`：会议列表、会议详情、录音、笔记、转写、AI、设置
- `Shared`：通用组件、常量、扩展

## 5. 目录结构

```text
piedras/
  App/
    PiedrasApp.swift
    AppContainer.swift
    AppRouter.swift
  Data/
    Models/
      Meeting.swift
      TranscriptSegment.swift
      ChatMessage.swift
    Persistence/
      ModelContainerFactory.swift
      MeetingRepository.swift
    Adapters/
      PlainTextHTMLAdapter.swift
      MeetingPayloadMapper.swift
  Services/
    Network/
      APIClient.swift
      StreamTextReader.swift
      WorkspaceBootstrapService.swift
    Audio/
      AudioSessionCoordinator.swift
      AudioRecorderService.swift
      PCMConverter.swift
      WaveformAnalyzer.swift
    ASR/
      ASRService.swift
      AliyunASRProtocol.swift
    Sync/
      MeetingSyncService.swift
  Stores/
    MeetingStore.swift
    SettingsStore.swift
    RecordingSessionStore.swift
  Features/
    MeetingList/
      MeetingListView.swift
      MeetingRowView.swift
    MeetingDetail/
      MeetingDetailView.swift
      DetailTabBar.swift
    Recording/
      RecordingView.swift
      RecordingControlBar.swift
      WaveformView.swift
    Transcript/
      TranscriptView.swift
    Notes/
      NoteEditorView.swift
    AI/
      EnhancedNotesView.swift
      ChatView.swift
      MessageBubble.swift
    Settings/
      SettingsView.swift
  Shared/
    Extensions/
    Constants/
```

## 6. 数据模型设计

### 6.1 Meeting

- `id: String`
- `title: String`
- `date: Date`
- `status: String`
- `durationSeconds: Int`
- `userNotesPlainText: String`
- `enhancedNotes: String`
- `audioLocalPath: String?`
- `audioRemotePath: String?`
- `audioMimeType: String?`
- `audioDuration: Int`
- `audioUpdatedAt: Date?`
- `hiddenWorkspaceId: String?`
- `syncState: String`
- `lastSyncedAt: Date?`
- `createdAt: Date`
- `updatedAt: Date`
- `segments: [TranscriptSegment]`
- `chatMessages: [ChatMessage]`

### 6.2 TranscriptSegment

- `id: String`
- `speaker: String`
- `text: String`
- `startTime: Double`
- `endTime: Double`
- `isFinal: Bool`
- `orderIndex: Int`

### 6.3 ChatMessage

- `id: String`
- `role: String`
- `content: String`
- `timestamp: Date`
- `orderIndex: Int`

### 6.4 关键建模约束

- 所有主键使用 `String`，直接兼容 web 端 UUID 字符串。
- `Meeting.status` 保留 `idle / recording / paused / ended`。
- `Meeting.syncState` 使用 `pending / syncing / synced / failed / deleted`。
- `TranscriptSegment` 和 `ChatMessage` 显式保存 `orderIndex`，不依赖关系数组顺序。
- iOS 本地只存纯文本笔记，不存富文本。

## 7. 本地存储策略

### 7.1 持久化方案

- 从当前模板的 `CoreData` 完整切换到 `SwiftData`。
- 删除模板里的 `Item` 模型和 `.xcdatamodeld`。
- 所有持久化读写经由 `MeetingRepository` 完成。

### 7.2 查询规则

- 首页列表按 `updatedAt DESC` 排序。
- 搜索覆盖：
  - `title`
  - `userNotesPlainText`
  - `enhancedNotes`
  - `TranscriptSegment.text`
- 详情优先读本地，必要时再远端 hydrate。

### 7.3 删除规则

- 本地未同步会议：直接本地硬删除。
- 已同步会议：先标记 `deleted`，同步成功后真正删除。
- 删除会议必须同时删除本地音频目录。

## 8. 后端兼容策略

### 8.1 隐藏 Workspace

虽然 iOS UI 不展示 workspace，但现有后端 `Meeting.workspaceId` 是必填，因此客户端内部保留一个隐藏默认 workspace。

规则如下：

- App 首次联网启动先调用 `GET /api/workspaces`。
- 如果为空，则自动调用 `POST /api/workspaces` 创建一个默认工作区。
- 返回的 `workspaceId` 保存到本地设置。
- 所有 iOS meeting 上传都自动带上这个 `workspaceId`。
- 用户层完全不可见。

### 8.2 Notes 兼容策略

web 端 `userNotes` 当前是 HTML/Tiptap 存储格式，iOS 改为纯文本：

- 下行：HTML 转纯文本。
- 上行：纯文本转最小 HTML 段落结构。
- 保证 web 端依然可读，iOS 端依然极简。

### 8.3 搜索兼容策略

现有 `GET /api/meetings` 搜索只覆盖 `title` 和 `enhancedNotes`，不能满足 iOS 搜索 transcript 的需求。

因此 iOS 采用：

- 列表刷新使用远端摘要同步。
- 搜索完全基于本地 SwiftData。

## 9. 音频架构

### 9.1 录音能力

- `AVAudioSession` 由 `AudioSessionCoordinator` 统一管理。
- `AVAudioRecorder` 负责写完整音频文件。
- `AVAudioEngine` 负责采样 PCM 和实时音量。
- 文件路径统一为：
  - `Application Support/Meetings/<meetingId>/recording.m4a`

### 9.2 波形与音量

- UI 波形只展示最近一段音量采样值。
- 不保存完整原始波形历史。
- 对外暴露归一化 `0...1` 的音量值供 UI 渲染。

### 9.3 PCM 转换

- 不采用手写平均降采样。
- 使用 `AVAudioConverter` 转换为：
  - `16000 Hz`
  - `mono`
  - `Int16 PCM`
- 输出格式与现有 web 阿里云 ASR 协议对齐。

## 10. ASR 架构

### 10.1 会话建立

- 录音开始时先调用 `GET /api/asr/status`
- 若 ASR ready，则调用 `POST /api/asr/session`
- 获取：
  - `wsUrl`
  - `token`
  - `appKey`
  - `vocabularyId`

### 10.2 WebSocket 协议

完全复用现有 web 协议：

- `StartTranscription`
- `TranscriptionStarted`
- `TranscriptionResultChanged`
- `SentenceEnd`
- `StopTranscription`

### 10.3 转写落库规则

- `partial` 只保存在内存态，不落库。
- `SentenceEnd` 才创建最终 `TranscriptSegment`。
- `segments` 始终保持有序。

### 10.4 降级策略

- ASR 状态失败时，不阻止录音本身。
- WebSocket 中断时，保留已有 final transcript。
- 回前台后可尝试恢复后续转写。

## 11. 前后台行为

### 11.1 录音开始

- 点击“新录音”时立刻创建本地 draft meeting。
- 用户直接进入会议详情页。
- 录音立即开始，不等待录音结束后再建会议。

### 11.2 Pause / Resume

- `pause`：暂停录音、停止 PCM 发送、结束当前 ASR task。
- `resume`：恢复录音并重建新的 ASR task。
- pause 时间不计入时长。

### 11.3 进入后台

- 本地录音继续。
- WebSocket ASR 关闭。
- partial transcript 清空。
- 不做后台实时转写。

### 11.4 回到前台

- 如果录音仍在继续，则重建 ASR 会话。
- 只转写回前台之后的新音频。
- 后台空窗期 transcript 缺失是设计内行为。

### 11.5 异常恢复

- App 冷启动时扫描所有 `recording / paused` meeting。
- 统一修正为 `ended + pending sync`。
- 保留本地音频。

## 12. UI 结构

### 12.1 首页 MeetingList

- 顶部搜索栏
- “新录音”按钮
- 会议列表项
- 下拉刷新
- 删除

列表项展示：

- 标题
- 更新时间
- 时长
- transcript 数量
- 同步状态

### 12.2 详情 MeetingDetail

- 顶部标题栏
- 同步状态
- 录音状态
- 主体采用三段切换：
  - `Notes`
  - `Transcript`
  - `AI`
- 底部为录音控制条或播放控制条

### 12.3 Notes

- 仅 `TextEditor`
- 无富文本工具栏
- `1.5s debounce` 自动保存

### 12.4 Transcript

- 顶部显示当前 partial
- 列表显示 final transcript
- 支持搜索
- 支持删除单段
- 支持点击定位到音频播放时间

### 12.5 AI

- 一个“生成 AI 总结”按钮
- 一个总结结果区域
- 一个单会议聊天区
- 不提供 recipe/template/provider 切换

### 12.6 Settings

- 后端地址
- ASR 健康状态
- 隐藏 workspace 状态
- 手动同步
- 清理缓存

## 13. 状态管理

### 13.1 MeetingStore

负责：

- 会议列表
- 详情装载
- 创建/删除会议
- 搜索过滤
- 同步入口
- AI 总结
- AI 问答

### 13.2 RecordingSessionStore

负责：

- 当前录音阶段
- 波形
- 时长
- 当前 partial transcript
- ASR 状态
- 错误提示

### 13.3 SettingsStore

负责：

- `backendBaseURL`
- `hiddenWorkspaceId`
- 健康检查结果
- bootstrap 状态

## 14. 同步策略

### 14.1 拉取

- App 启动时
- 下拉刷新时
- 回到前台时

调用：

- `GET /api/meetings?workspaceId=<hiddenWorkspaceId>`

### 14.2 推送

以下场景把 meeting 标记为 `pending`：

- 录音停止
- 笔记修改
- 删除 segment
- AI 总结成功
- chat 成功结束

推送流程：

1. `POST /api/meetings`
2. 若有音频更新，再 `POST /api/meetings/{id}/audio`
3. 若标题为空且 meeting 已结束，可调用 `POST /api/meetings/title`

### 14.3 冲突规则

- 本地 `pending / failed` 优先，不被远端覆盖。
- 本地 `synced` 才允许被远端较新版本覆盖。
- 不做细粒度 merge。

## 15. AI 规格

### 15.1 自动标题

- 仅在 meeting 停止后且标题为空时触发一次。
- 失败不阻断正常保存。

### 15.2 AI 总结

- 调用 `POST /api/enhance`
- 输入：
  - transcript 全文
  - 纯文本笔记
  - 标题
- 当前后端接口是非流式 JSON 返回，因此 iOS 只做 loading 态。

### 15.3 单会议 Chat

- 调用 `POST /api/chat`
- 读取 `text/plain` 流式响应
- user message 立即本地保存
- assistant message 流结束后再持久化最终内容

## 16. 工程配置

### 16.1 Xcode

- 保留当前 `piedras` target
- 删除模板 `ContentView.swift`
- 删除模板 `Persistence.swift`
- 删除 `.xcdatamodeld`
- deployment target 下调到 `iOS 17.0`

### 16.2 权限

- `NSMicrophoneUsageDescription`
- `UIBackgroundModes = audio`

### 16.3 ATS / Base URL

- Debug 支持本地开发地址
- Release 默认使用 HTTPS
- 真机联调由设置页填写局域网地址

## 17. 分阶段实施

### Phase 1 工程骨架

- 删掉模板壳代码
- 建立目录结构
- 接入 SwiftData
- 建立 AppContainer 与基础路由

### Phase 2 本地数据与列表

- 完成 Meeting 模型
- 完成 Repository
- 完成列表、本地搜索、删除

### Phase 3 录音能力

- 完成 AVAudioSession 配置
- 完成录音文件保存
- 完成波形与时长
- 完成 pause / resume / stop

### Phase 4 ASR

- 完成 `/api/asr/status`
- 完成 `/api/asr/session`
- 完成 WebSocket ASR
- 打通 partial/final transcript

### Phase 5 详情页

- 完成 Notes / Transcript / AI 三块
- 完成播放器
- 完成 transcript 定位

### Phase 6 AI 能力

- 自动标题
- AI 总结
- 单会议 chat

### Phase 7 同步与设置

- workspace bootstrap
- meeting pull / push / delete
- 设置页与健康检查

### Phase 8 打磨与测试

- 前后台行为验证
- 错误态统一
- 测试补齐
- 构建与回归

## 18. 测试计划

### 18.1 单元测试

- PCM 转换
- 波形 RMS
- HTML / 纯文本适配
- payload 编解码
- 文本流读取
- workspace bootstrap

### 18.2 集成测试

- 新录音立即创建 draft meeting
- 停止后本地音频存在且可播放
- `SentenceEnd` 能正确落库
- ASR 不可用时录音照常工作
- 笔记可自动保存
- 删除 segment 后本地与同步行为正确
- AI 总结与 chat 均可成功持久化

### 18.3 同步测试

- 首次启动自动 bootstrap workspace
- 离线创建 meeting 后联网补同步
- 录音结束后自动上传 meeting + audio
- 拉取远端摘要导入本地
- 本地 pending 不被远端覆盖

### 18.4 前后台测试

- 切后台后录音不中断
- 回前台后时长连续
- 回前台后转写继续
- 后台空窗 transcript 缺失为设计内行为

## 19. 验收标准

- 用户可以直接开始一场录音会议。
- 录音、暂停、恢复、停止稳定可用。
- 本地音频可保存、可回放。
- 前台实时转写可用，失败时不影响录音。
- 用户可随时编辑纯文本笔记。
- AI 总结与单会议 AI 问答可用。
- 会议列表支持搜索、删除、离线查看。
- 后台录音不中断。
- 所有 key 仍只保留在服务端。

## 20. 默认假设

- 无登录、无账号体系。
- 单用户、单设备优先。
- iOS 不暴露 workspace。
- iOS 不提供富文本编辑。
- iOS 不提供复杂的 AI 参数配置。
- AI 总结非流式，chat 为文本流式。
- 现有 Next.js 后端继续作为唯一服务端来源。

