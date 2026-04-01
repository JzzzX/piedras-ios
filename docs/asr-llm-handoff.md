# Piedras ASR / LLM 技术交接说明

## 适用范围

本文面向接手 `piedras` 当前服务端 AI 能力的同事，重点覆盖：

- 实时 ASR 链路
- 离线补转写链路
- LLM 聊天与 AI 笔记链路
- Zeabur 线上部署现状
- 已知不稳定点与排查顺序

本文基于 `2026-04-01` 的仓库与线上状态整理。

## 一句话结论

截至 `2026-04-01`，线上主链路并不是“ASR 和 LLM 整体不可用”，而是：

- 主入口服务当前在线，基础健康检查正常
- 实时 ASR 可用，但它对公网回探、WS 路径和 session 签发有较强依赖
- LLM 当前已收敛到 AiHubMix 单 provider，普通文本链路可用，但仍要关注上游 429 / 5xx 与超时
- 仓库中的“推荐部署形态”和当前 Zeabur 上的“真实资源形态”存在偏差，接手时要先认清现状

## 当前线上真实现状

### 1. 当前公网入口

当前线上域名为：

```text
https://piedras.preview.aliyun-zeabur.cn
```

`2026-04-01` 实测结果：

```bash
curl https://piedras.preview.aliyun-zeabur.cn/healthz
curl https://piedras.preview.aliyun-zeabur.cn/api/asr/status
curl https://piedras.preview.aliyun-zeabur.cn/api/llm/status
curl https://piedras.preview.aliyun-zeabur.cn/asr-proxy/healthz
```

返回均正常，其中：

- `/healthz` 返回数据库与启动初始化状态正常
- `/api/asr/status` 返回 `mode=doubao`、`provider=doubao-proxy`、`ready=true`
- `/api/llm/status` 应返回 `provider=aihubmix`、`preset=aihubmix`、`model=gemini-3-flash-preview`、`ready=true`
- `/asr-proxy/healthz` 返回内置 ASR 代理可达

### 2. Zeabur 当前资源形态

当前 Zeabur 账号下至少存在两个相关项目：

- `piedras`
- `piedras-asr`

其中与线上域名真正对应的是：

- Project: `piedras`
- Service: `piedras-ios`
- Root Directory: `cloud/api`
- Domain: `piedras.preview.aliyun-zeabur.cn`

另外还有一个独立项目：

- Project: `piedras-asr`
- Service: `piedras-asr`
- Root Directory: `cloud/asr-proxy`

但截至本次核查，这个独立 `piedras-asr` 服务表现更像历史遗留资源，而不是当前正式流量入口：

- 没有查到域名
- 没有查到部署记录
- 没有查到自定义环境变量

### 3. 文档推荐形态与真实运行形态不完全一致

仓库内 [cloud-deployment.md](/Users/a123456/Desktop/piedras/docs/cloud-deployment.md) 推荐的是“单入口 Zeabur 承载 `cloud/api + ASR proxy`”。

当前线上实际情况更接近：

- 正式流量由 `cloud/api` 单服务承载
- `cloud/api/server.cjs` 内嵌了豆包 ASR WebSocket 代理能力
- 另外还保留了一个独立 `cloud/asr-proxy` 对应的 Zeabur 项目，但从核查结果看并未承担当前线上流量

这意味着接手时不要先入为主地认为“线上一定是双服务共同在跑”。

## 代码与线上版本差异

### 1. 当前线上部署版本

本次通过 Zeabur deployment 看到：

- 当前线上 `piedras-ios` 最新部署 commit 为 `f197063b54fe02c6e487c6473dbd1c8ee7a11d0d`
- commit message 为 `fix(ai): 兼容音频 AI 笔记的 m4a 输入`
- 创建时间为 `2026-03-31T12:42:18Z`

### 2. 当前本地仓库状态

本地工作区当前：

- `HEAD` 为 `8fb752f9dbb031a77be2950dcaff1189e02a7b94`
- 本地 `main` 落后 `origin/main` 4 个提交
- `origin/main` 指向 `f197063b54fe02c6e487c6473dbd1c8ee7a11d0d`

因此，接手排障前必须先明确自己在看哪一版：

- 如果排线上问题，先以线上部署 commit 为准
- 不要直接拿本地当前 `main` 推断线上行为

## ASR 链路说明

### 实时 ASR 主链路

当前实时 ASR 逻辑是：

1. iOS 调用 `POST /api/asr/session`
2. `cloud/api` 校验豆包 ASR 配置与代理健康状态
3. `cloud/api` 生成带签名的 `session_token`
4. iOS 拿到 `wsUrl` 后直连服务端暴露的 WS 路径
5. 服务端内置代理再把音频转发给豆包上游 WS

关键代码：

- [asr.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/asr.ts)
- [route.ts](/Users/a123456/Desktop/piedras/cloud/api/app/api/asr/session/route.ts)
- [server.cjs](/Users/a123456/Desktop/piedras/cloud/api/server.cjs)

### 实时 ASR 的几个关键依赖

实时 ASR 是否能真正建立，会同时依赖：

- `ASR_MODE=doubao`
- `DOUBAO_ASR_APP_ID`
- `DOUBAO_ASR_ACCESS_TOKEN`
- `DOUBAO_ASR_RESOURCE_ID`
- `ASR_PROXY_SESSION_SECRET`
- `ASR_PROXY_PUBLIC_BASE_URL`
- `ASR_PROXY_HEALTH_PATH`
- `ASR_PROXY_WS_PATH`

其中最容易被忽略的是：

- `POST /api/asr/session` 在签发 session 之前，会先探测公网 `ASR_PROXY_PUBLIC_BASE_URL + ASR_PROXY_HEALTH_PATH`
- 如果这个回探失败，session 不会签发，即使豆包凭据本身没问题

对应代码见 [asr.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/asr.ts#L158) 和 [route.ts](/Users/a123456/Desktop/piedras/cloud/api/app/api/asr/session/route.ts#L175)。

### 这条链路为什么“看起来容易不稳定”

因为它跨了多个边界：

- iOS 到 `cloud/api`
- `cloud/api` 到自身公网 health 地址回探
- iOS 到服务端 WebSocket
- 服务端代理到豆包上游 WebSocket

任何一层出问题，用户感知都可能是“实时字幕不出了”。

### iOS 端当前降级策略

iOS 端并不是“实时 ASR 一失败，录音就报废”。

当前策略是：

- 实时链路失败时，录音继续
- 状态转为 `degraded`
- 会尝试自动重连
- 结束录音后会走补转写或后台补齐逻辑

关键代码：

- [ASRService.swift](/Users/a123456/Desktop/piedras/piedras/Services/Network/ASRService.swift#L28)
- [MeetingStore.swift](/Users/a123456/Desktop/piedras/piedras/Stores/MeetingStore.swift#L2703)

所以排障时要区分两类问题：

- 实时能力退化：用户看不到实时字幕，但录音和最终文本可能仍能保住
- 数据链路失败：录音、音频上传、补转写或最终保存真的失败

这两类问题优先级不同，不要混在一起判断。

## 离线补转写链路

录音结束或上传音频后，服务端可以走离线补转写：

- 音频会先转码
- 再调用火山引擎/豆包离线识别接口
- 最终写回 `segments` 和 `speakers`

关键代码：

- [meeting-transcript-finalizer.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/meeting-transcript-finalizer.ts)
- [audio route.ts](/Users/a123456/Desktop/piedras/cloud/api/app/api/meetings/[id]/audio/route.ts)

### 离线补转写的关键依赖

- 运行环境里必须有 `ffmpeg`
- 需要 `VOLCENGINE_FILE_ASR_*` 或复用 `DOUBAO_ASR_*`

当前 `cloud/api/Dockerfile` 已显式安装 `ffmpeg`，见 [Dockerfile](/Users/a123456/Desktop/piedras/cloud/api/Dockerfile)。

### 已知注意点

- `/api/asr/status` 绿，只能说明实时代理健康，不代表离线补转写一定没问题
- 离线补转写依赖另一条上游接口，排障时不要只盯着实时 WS

## LLM 链路说明

### 当前主 LLM 路径

当前服务端 LLM 主链路固定为：

- provider: `aihubmix`
- preset: `aihubmix`
- model: `gemini-3-flash-preview`

这表示当前主链路是：

- 代码层只保留 AiHubMix 一个 provider
- 上游模型固定走 `gemini-3-flash-preview`

关键代码：

- [llm-config.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/llm-config.ts)
- [llm-provider.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/llm-provider.ts)
- [llm-health.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/llm-health.ts)

### 当前线上环境变量的实际含义

当前应当只保留以下 LLM 变量：

- `AIHUBMIX_API_KEY`
- `AIHUBMIX_BASE_URL`
- `AIHUBMIX_MODEL`
- `AIHUBMIX_PATH`
- `LLM_PROVIDER=aihubmix`

不再需要：

- `OPENAI_*`
- `GEMINI_API_KEY`
- `MINIMAX_*`
- `LLM_FALLBACKS`

### `/api/llm/status` 的局限性

`/api/llm/status` 当前只是用一个很小的 probe 请求验证主 provider 是否能响应。

它能回答的是：

- 当前配置是否存在
- 当前主 provider 是否能返回一个极小文本结果

它不能回答的是：

- 长上下文是否稳定
- 音频理解链路是否稳定
- 长音频转码链路是否稳定
- 高峰时段 AiHubMix 上游是否抖动

对应代码见 [llm-health.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/llm-health.ts#L106) 和 [llm-provider.ts](/Users/a123456/Desktop/piedras/cloud/api/lib/llm-provider.ts#L715)。

## 音频 AI 笔记当前也统一走 AiHubMix

音频 AI 笔记链路已经改成单一路径：

- 服务端统一先转成单声道 `mp3`
- 请求体统一走 inline audio
- 不再依赖 Gemini Files API

这意味着现在的风险点主要是：

- `ffmpeg` 转码失败
- 长音频导致总耗时偏大
- AiHubMix 上游在音频理解场景下超时或限流

## 已知不稳定点清单

接手时建议把风险按下面几类记：

### A. 实时 ASR 入口类问题

表现：

- 录音开始后没有实时字幕
- `createASRSession` 直接失败
- WS 建立后很快断开

常见原因：

- `ASR_PROXY_PUBLIC_BASE_URL` 配置不对
- `ASR_PROXY_HEALTH_PATH` / `ASR_PROXY_WS_PATH` 不一致
- 外部域名可访问，但服务端回探失败
- 豆包上游 WS 抖动
- `session_token` 签名或过期问题

优先检查：

- `/api/asr/status`
- `/asr-proxy/healthz`
- `cloud/api` 日志中的 `proxy_ready`、`upstream_closed`、`session_token_invalid`

### B. 实时 ASR 能力退化但数据未必丢失

表现：

- 用户看不到实时 partial/final
- 录音本身还在继续
- 停止录音后最终仍可能有完整文本

这类问题优先级低于“最终结果丢失”，因为客户端已有降级处理。

### C. 离线补转写问题

表现：

- 录音结束后一直没有完整转写
- 上传音频后 `segments` 没落库

常见原因：

- 离线识别上游失败
- `ffmpeg` 转码失败
- 音频文件落盘或读取异常

### D. LLM 文本链路问题

表现：

- 聊天接口报错
- AI 标题 / AI 增强笔记失败

常见原因：

- `AIHUBMIX_*` 配置异常
- AiHubMix 上游 429 / 5xx
- `LLM_TIMEOUT_MS` 偏紧
- 代理层误把占位文本当成成功响应

### E. 音频 AI 笔记问题

表现：

- 普通聊天正常
- 音频 AI 笔记在长音频或特定格式下报错

优先检查：

- `ffmpeg` 是否可用
- 输入音频是否损坏
- 是否出现 AiHubMix 超时 / 429 / 5xx

## 建议排查顺序

接到问题后，建议按这个顺序查：

1. 先确认线上排查基准版本
2. 先看健康接口是否全绿
3. 再判断是实时 ASR、离线补转写，还是 LLM / 音频 AI 笔记问题
4. 不要把“实时字幕失败”直接等同于“数据丢失”
5. 不要把“`/api/llm/status` 正常”直接等同于“音频 AI 功能没问题”

推荐命令：

```bash
curl https://piedras.preview.aliyun-zeabur.cn/healthz
curl https://piedras.preview.aliyun-zeabur.cn/api/asr/status
curl https://piedras.preview.aliyun-zeabur.cn/api/llm/status
curl https://piedras.preview.aliyun-zeabur.cn/asr-proxy/healthz
```

如果要验证实时 ASR：

```bash
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav https://piedras.preview.aliyun-zeabur.cn <bearer-token>
```

## Zeabur 接手清单

接手后建议第一时间确认以下内容：

### 服务与流量

- `piedras.preview.aliyun-zeabur.cn` 现在究竟绑定哪个 service
- `piedras-asr` 是否已经完全废弃
- 是否还存在团队成员误以为线上是双服务架构

### 部署版本

- 当前正在运行的 deployment id 与 commit
- 是否需要先把本地代码切到 `origin/main`

### 环境变量

- `ASR_*` 相关变量是否完整
- `AIHUBMIX_*` 是否完整且只保留这一套
- `LLM_PROVIDER` 是否明确为 `aihubmix`
- 是否还残留历史 `OPENAI_*` 变量

### 日志关注点

建议重点关注：

- `session_token_invalid`
- `upstream_closed`
- 豆包 ASR 初始化失败
- LLM 429 / 5xx
- 音频转码失败

## 首次接手建议动作

如果由新同事正式接手，建议第一轮只做下面几件事：

1. 把本地代码先对齐到 `origin/main`
2. 再次确认 Zeabur 上真正在线的 service、domain、deployment
3. 固化一份当前线上环境变量清单，只记录 key，不记录 secret 值
4. 用一个小音频跑通实时 ASR smoke test
5. 用一个长音频样本验证音频 AI 笔记在转码和上游响应上是否稳定
6. 决定是否正式下线 `piedras-asr` 这个独立项目，避免后续认知混乱

## 最后提醒

接手这个模块时，最容易犯的两个错误是：

- 误把“实时 ASR 降级”当成“录音数据丢失”
- 误把“LLM 状态接口正常”当成“所有 AI 功能稳定”

只要先把这两个边界分清，后续排障效率会高很多。
