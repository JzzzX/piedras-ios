# Home Screen UI Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 精简主页 Dock 栏（移除音频上传按钮）、更新录音按钮图标为麦克风+笔组合、移除下拉日期指示器。

**Architecture:** 所有改动集中于单一文件 `MeetingListView.swift`，分三次独立提交，每次改动互不依赖。

**Tech Stack:** SwiftUI, iOS, xcodebuild iphonesimulator

---

## File Map

| 文件 | 操作 |
|------|------|
| `piedras/Features/MeetingList/MeetingListView.swift` | Modify（三处改动） |

---

### Task 1: 移除音频上传按钮及相关代码

**Files:**
- Modify: `piedras/Features/MeetingList/MeetingListView.swift`

- [ ] **Step 1: 移除 `@State private var isImportingSourceAudio`**

在文件约 line 49，删除：
```swift
@State private var isImportingSourceAudio = false
```

- [ ] **Step 2: 移除 `unifiedBottomDock` 中的上传按钮和第一条分隔线**

找到 `private var unifiedBottomDock: some View` （约 line 335），将整个 `HStack` 内容从：
```swift
HStack(spacing: 14) {
    dockIconButton(
        systemName: "waveform.badge.plus",
        accessibilityLabel: "上传音频",
        identifier: "HomeUploadAudioButton",
        action: openUploadAudio
    )

    Rectangle()
        .fill(AppTheme.subtleBorderColor)
        .frame(width: AppTheme.subtleBorderWidth, height: 28)

    recordingButton(size: 58)

    Rectangle()
        .fill(AppTheme.subtleBorderColor)
        .frame(width: AppTheme.subtleBorderWidth, height: 28)

    homeChatLauncher
}
```
改为：
```swift
HStack(spacing: 14) {
    recordingButton(size: 58)

    Rectangle()
        .fill(AppTheme.subtleBorderColor)
        .frame(width: AppTheme.subtleBorderWidth, height: 28)

    homeChatLauncher
}
```

- [ ] **Step 3: 移除 `.fileImporter` 修饰符**

找到 `body` 中的 `.fileImporter(isPresented: $isImportingSourceAudio, ...)` 块（约 line 81），删除以下代码：
```swift
.fileImporter(
    isPresented: $isImportingSourceAudio,
    allowedContentTypes: [.audio],
    allowsMultipleSelection: false
) { result in
    handleSourceAudioSelection(result)
}
```

- [ ] **Step 4: 删除 `openUploadAudio()` 函数**

找到并删除（约 line 574）：
```swift
private func openUploadAudio() {
    isImportingSourceAudio = true
}
```

- [ ] **Step 5: 删除 `handleSourceAudioSelection(_:)` 函数**

找到并删除（约 line 590）：
```swift
private func handleSourceAudioSelection(_ result: Result<[URL], Error>) {
    switch result {
    case let .success(urls):
        guard let sourceURL = urls.first else { return }
        guard let meeting = meetingStore.createMeeting() else { return }
        router.showMeeting(id: meeting.id)
        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        Task {
            await meetingStore.startFileTranscription(
                meetingID: meeting.id,
                sourceAudio: SourceAudioAsset(
                    fileURL: sourceURL,
                    displayName: displayName
                )
            )
        }
    case let .failure(error):
        meetingStore.lastErrorMessage = error.localizedDescription
    }
}
```

- [ ] **Step 6: 构建验证**

```bash
cd /Users/a123456/Desktop/piedras && xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator build 2>&1 | tail -5
```
期望输出：`** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
cd /Users/a123456/Desktop/piedras && git add piedras/Features/MeetingList/MeetingListView.swift && git commit -m "feat(ios): 移除主页音频上传按钮及相关逻辑"
```

---

### Task 2: 录音按钮图标改为麦克风+笔组合

**Files:**
- Modify: `piedras/Features/MeetingList/MeetingListView.swift`

- [ ] **Step 1: 修改 `recordingButton(size:)` 的空闲状态图标**

找到 `recordingButton(size:)` 函数（约 line 408）中的 label ZStack，将：
```swift
ZStack {
    Rectangle()
        .fill(recordingSessionStore.phase == .idle ? AppTheme.surface : AppTheme.highlight)

    Image(systemName: recordingSessionStore.phase == .idle ? "mic.fill" : "stop.fill")
        .font(.system(size: size * 0.30, weight: .bold))
        .foregroundStyle(recordingSessionStore.phase == .idle ? AppTheme.ink : .white)
}
```
改为：
```swift
ZStack {
    Rectangle()
        .fill(recordingSessionStore.phase == .idle ? AppTheme.surface : AppTheme.highlight)

    if recordingSessionStore.phase == .idle {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .offset(x: -3, y: -3)

            Image(systemName: "pencil")
                .font(.system(size: size * 0.14, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .offset(x: 4, y: 4)
        }
    } else {
        Image(systemName: "stop.fill")
            .font(.system(size: size * 0.30, weight: .bold))
            .foregroundStyle(.white)
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
cd /Users/a123456/Desktop/piedras && xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator build 2>&1 | tail -5
```
期望输出：`** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd /Users/a123456/Desktop/piedras && git add piedras/Features/MeetingList/MeetingListView.swift && git commit -m "feat(ios): 录音按钮图标改为麦克风+笔组合"
```

---

### Task 3: 移除下拉日期指示器

**Files:**
- Modify: `piedras/Features/MeetingList/MeetingListView.swift`

- [ ] **Step 1: 从 `feedList` 移除 `pullToRefreshDateHeader`**

找到 `private var feedList: some View` 中的 `List { }` 内容（约 line 196），删除第一行：
```swift
// 下拉刷新日期指示器 (Granola 风格)
pullToRefreshDateHeader
```

- [ ] **Step 2: 删除 `pullToRefreshDateHeader` 计算属性**

找到并删除整个属性（约 line 160）：
```swift
private var pullToRefreshDateHeader: some View {
    VStack(spacing: 4) {
        Text(formattedCurrentDate)
            .ptrDateFont() // 优先使用宋体
            .foregroundStyle(AppTheme.subtleInk)
            .frame(maxWidth: .infinity)
            .opacity(min(1.0, max(0.0, (Double(scrollOffset) + 60.0) / 40.0))) // 随拉动显示
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .frame(height: max(0, scrollOffset > 0 ? 0 : -scrollOffset))
}
```

- [ ] **Step 3: 删除 `formattedCurrentDate` 计算属性**

找到并删除（约 line 174）：
```swift
private var formattedCurrentDate: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: settingsStore.appLanguage.rawValue)
    formatter.dateFormat = "MMMM d, EEEE"
    if settingsStore.appLanguage == .chinese {
        // 中文特殊格式
        let month = Calendar.current.component(.month, from: .now)
        let day = Calendar.current.component(.day, from: .now)
        let weekday = formatter.weekdaySymbols[Calendar.current.component(.weekday, from: .now) - 1]
        return "\(numberToChinese(month))月\(numberToChinese(day))日，\(weekday)"
    }
    return formatter.string(from: .now)
}
```

- [ ] **Step 4: 删除 `numberToChinese(_:)` 函数**

找到并删除（约 line 188）：
```swift
private func numberToChinese(_ n: Int) -> String {
    let chineseNumbers = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十", "二十一", "二十二", "二十三", "二十四", "二十五", "二十六", "二十七", "二十八", "二十九", "三十", "三十一"]
    if n < chineseNumbers.count {
        return chineseNumbers[n]
    }
    return "\(n)"
}
```

- [ ] **Step 5: 删除 `ptrDateFont()` View 扩展方法**

找到文件顶部的 `private extension View` 块（约 line 4），删除 `ptrDateFont()` 方法：
```swift
func ptrDateFont() -> some View {
    self.font(.custom("STSong", size: 14))
}
```
若此时 `private extension View` 块内还有 `appHeaderFont()`，则只删除 `ptrDateFont()` 方法，保留扩展块；若块内为空则可删除整个扩展块。

- [ ] **Step 6: 构建验证**

```bash
cd /Users/a123456/Desktop/piedras && xcodebuild -project Piedras.xcodeproj -scheme piedras -configuration Debug -sdk iphonesimulator build 2>&1 | tail -5
```
期望输出：`** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
cd /Users/a123456/Desktop/piedras && git add piedras/Features/MeetingList/MeetingListView.swift && git commit -m "feat(ios): 移除主页下拉日期指示器"
```
