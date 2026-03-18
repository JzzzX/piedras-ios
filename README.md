# Piedras iOS

Piedras iOS 是一个聚焦录音、实时转写、纯文本笔记与单会议 AI 总结/问答的原生 iOS App。

当前仓库用于承载 iOS MVP 的独立开发与版本管理，服务端继续复用现有 `ai_notepad` Next.js API。

## 默认运行方式

- App 默认连接固定云后端 `https://piedras-api.vercel.app`
- LLM 走 AiHubMix 的 OpenAI-compatible 后端
- ASR 走豆包实时识别 + 独立 WebSocket 代理
- 普通用户路径不再依赖本地 `localhost` 或局域网地址配置

## 文档

- 详细方案见 [docs/piedras-ios-mvp-plan.md](docs/piedras-ios-mvp-plan.md)
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

## 提交信息规范

本仓库采用 Conventional Commits，提交说明使用中文。

示例：

```text
feat: 完成会议列表和本地搜索
fix: 修复录音停止后音频文件未同步问题
docs: 更新 iOS MVP 架构计划
```
