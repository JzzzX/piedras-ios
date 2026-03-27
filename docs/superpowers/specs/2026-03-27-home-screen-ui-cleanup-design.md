# Home Screen UI Cleanup — Design Spec

**Date:** 2026-03-27
**Scope:** `piedras/Features/MeetingList/MeetingListView.swift` only

## Context

用户希望精简主页界面：去掉几乎没有使用的音频上传按钮、减少顶部空白（移除下拉日期指示器）、并将录音按钮图标改为更有辨识度的「麦克风+记笔记」组合图标。

---

## Change 1: 移除音频上传按钮

**位置：** `unifiedBottomDock` 计算属性（约 line 335）

**移除内容：**
- `dockIconButton(systemName: "waveform.badge.plus", ...)` 按钮
- 其后的第一条竖向分隔线 `Rectangle().fill(...).frame(width:, height: 28)`
- `@State private var isImportingSourceAudio = false`
- `.fileImporter(isPresented: $isImportingSourceAudio, ...)` 修饰符
- `openUploadAudio()` 函数
- `handleSourceAudioSelection(_:)` 函数

**结果布局：**
```
[  录音按钮  ] | [  AI 聊天  ]
```
录音按钮居左侧，聊天按钮居右，中间保留一条分隔线。

---

## Change 2: 录音按钮图标改为麦克风+笔组合

**位置：** `recordingButton(size:)` 函数（约 line 408）

**空闲状态（phase == .idle）：**

将单一 `Image(systemName: "mic.fill")` 替换为 ZStack 叠加：
- 主图标：`mic.fill`，尺寸 `size * 0.28`，偏移 `(-3, -3)`
- 角标图标：`pencil`，尺寸 `size * 0.14`，对齐 `.bottomTrailing`，偏移 `(4, 4)`，颜色同主图标

**录音中状态（phase != .idle）：**
保持现有 `stop.fill` 单图标不变。

---

## Change 3: 移除下拉日期指示器

**位置：** `feedList` 计算属性（约 line 196）

**移除内容：**
- `pullToRefreshDateHeader`（List 第一行，下拉刷新时显示的日期文本）
- `pullToRefreshDateHeader` 计算属性本身（约 line 160）
- `formattedCurrentDate` 计算属性（约 line 174）
- `numberToChinese(_:)` 函数（约 line 188）
- `ptrDateFont()` View 扩展方法（约 line 9）

**保留：**
- `header`（Piedras 大标题 + 搜索/设置按钮）—— 不变
- `compactHeader`（滚动后淡入的紧凑顶栏）—— 不变

---

## Files Modified

| 文件 | 改动 |
|------|------|
| `piedras/Features/MeetingList/MeetingListView.swift` | 所有三处改动 |

无需新建文件，无需修改 `AppTheme.swift`、`AppStrings.swift` 或其他文件。

---

## Verification

1. 构建并在模拟器运行：`xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator build`
2. 主页 Dock 只有两个元素：录音按钮 + AI 聊天按钮
3. 录音按钮空闲时显示 mic+pencil 组合图标
4. 点击录音按钮跳转录音界面，按钮变为 stop 图标
5. 下拉列表不再出现日期文字
6. 顶部 Piedras 大标题仍正常显示
7. 搜索和设置按钮仍可访问
