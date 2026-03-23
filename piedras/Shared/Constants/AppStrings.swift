import Foundation

// MARK: - Language Enum

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "EN"
        }
    }
}

// MARK: - String Table

struct AppStringTable {
    let language: AppLanguage

    private var isChinese: Bool { language == .chinese }

    // ── MeetingListView ──────────────────────────────────────────

    var appTitle: String { isChinese ? "Piedras 笔记" : "Piedras Notes" }
    var noNotesYet: String { isChinese ? "还没有笔记" : "No notes yet" }
    var tapMicToCapture: String { isChinese ? "点击麦克风开始你的第一条笔记。" : "Tap the mic to capture your first note." }
    var chatWithNotes: String { isChinese ? "与笔记对话" : "Chat with notes" }
    var uploadAudio: String { isChinese ? "上传音频" : "Upload audio" }
    var newRecording: String { isChinese ? "新录音" : "New recording" }
    var stop: String { isChinese ? "停止" : "Stop" }
    var deleteAction: String { isChinese ? "删除" : "Delete" }

    // ── MeetingHomeBucket ────────────────────────────────────────

    var bucketProcessing: String { isChinese ? "处理中" : "Processing" }
    var bucketToday: String { isChinese ? "今天" : "Today" }
    var bucketYesterday: String { isChinese ? "昨天" : "Yesterday" }
    var bucketEarlierThisWeek: String { isChinese ? "本周早些" : "Earlier this week" }
    var bucketEarlier: String { isChinese ? "更早" : "Earlier" }

    // ── MeetingDetailView ────────────────────────────────────────

    var transcript: String { isChinese ? "转写" : "Transcript" }
    var aiNotes: String { isChinese ? "AI 笔记" : "AI Notes" }
    var editTitle: String { isChinese ? "编辑标题" : "Edit title" }
    var editAINotes: String { isChinese ? "编辑 AI 笔记" : "Edit AI notes" }
    var showMyNotes: String { isChinese ? "查看我的笔记" : "Show my notes" }
    var copyNotes: String { isChinese ? "复制笔记" : "Copy notes" }
    var copyTranscript: String { isChinese ? "复制转写" : "Copy transcript" }
    var viewAINotes: String { isChinese ? "查看 AI 笔记" : "View AI notes" }
    var chatWithNote: String { isChinese ? "与笔记对话" : "Chat with note" }
    var copiedTranscript: String { isChinese ? "已复制转写" : "Copied transcript" }
    var copiedNotes: String { isChinese ? "已复制笔记" : "Copied notes" }
    var meetingNotExist: String { isChinese ? "会议不存在" : "Meeting not found" }
    var meetingMayBeDeleted: String { isChinese ? "这条会议可能已经被删除。" : "This meeting may have been deleted." }
    var untitledNote: String { isChinese ? "无标题笔记" : "Untitled note" }
    var untitledMeeting: String { isChinese ? "未命名会议" : "Untitled meeting" }
    var myNotes: String { isChinese ? "我的笔记" : "My notes" }
    var writeHere: String { isChinese ? "在此书写。" : "Write here." }
    var writeMarkdownHere: String { isChinese ? "在此写 Markdown。" : "Write markdown here." }
    var renameTitlePrompt: String { isChinese ? "输入新的笔记标题" : "Enter a new title for the note" }
    var notesTeaserEmpty: String { isChinese ? "记下想法，会并入 AI 笔记" : "Capture thoughts to blend into AI notes" }
    var notesTeaserContinue: String { isChinese ? "继续记录你的想法" : "Keep writing your thoughts" }
    var notesMergeHint: String { isChinese ? "这些随手笔记会在下次生成或刷新 AI 笔记时并入。" : "These notes will be blended into AI Notes the next time you generate or refresh them." }
    var notRecordedYet: String { isChinese ? "未录音" : "Not recorded yet" }
    var recording_suffix: String { isChinese ? "录音" : "recording" }
    var back: String { isChinese ? "返回" : "Back" }
    var share: String { isChinese ? "分享" : "Share" }
    var generatingNotes: String { isChinese ? "正在生成笔记" : "Generating notes" }
    var refreshNotes: String { isChinese ? "刷新笔记" : "Refresh notes" }
    var cancel: String { isChinese ? "取消" : "Cancel" }
    var save: String { isChinese ? "保存" : "Save" }
    var notes: String { isChinese ? "笔记" : "Notes" }
    var preparingImportedAudio: String { isChinese ? "正在准备音频..." : "Preparing audio..." }
    var connectingASR: String { isChinese ? "正在连接 ASR..." : "Connecting ASR..." }
    var finalizingTranscription: String { isChinese ? "正在整理转写..." : "Finalizing transcript..." }
    var audioTranscriptionFailed: String { isChinese ? "文件转写失败" : "Audio transcription failed" }
    var retryTranscription: String { isChinese ? "重新转写" : "Retry transcription" }
    var fileTranscriptionInterrupted: String { isChinese ? "应用中断了上次文件转写，请重新转写。" : "The previous file transcription was interrupted. Please retry." }

    func transcribingAudioProgress(elapsed: String, total: String) -> String {
        isChinese ? "正在转写 \(elapsed) / \(total)" : "Transcribing \(elapsed) / \(total)"
    }

    // ── Recording Dialog ─────────────────────────────────────────

    var chooseRecordingMode: String { isChinese ? "选择录音方式" : "Choose recording mode" }
    var micOnly: String { isChinese ? "仅麦克风" : "Microphone only" }
    var audioFilePlusMic: String { isChinese ? "音频文件 + 麦克风（高级）" : "Audio file + Microphone (Advanced)" }
    var chooseRecordingInput: String { isChinese ? "选择这次会议的录音输入。首页“上传音频”会直接执行文件转写。" : "Choose the recording input for this meeting. The home upload flow performs direct file transcription." }

    // ── MeetingSearchView ────────────────────────────────────────

    var search: String { isChinese ? "搜索" : "Search" }
    var searchNotesAndTranscript: String { isChinese ? "搜索笔记和转写" : "Search notes and transcript" }
    var startTyping: String { isChinese ? "开始输入。" : "Start typing." }
    var noMatch: String { isChinese ? "无结果。" : "No match." }
    var close: String { isChinese ? "关闭" : "Close" }

    // ── GlobalChatView ───────────────────────────────────────────

    var ask: String { isChinese ? "提问" : "Ask" }
    var allNotes: String { isChinese ? "所有笔记" : "All notes" }
    var askFromTranscript: String { isChinese ? "从转写、笔记和摘要中提问。" : "Ask from transcript, notes and summaries." }
    var suggestSummarize: String { isChinese ? "总结待定事项" : "Summarize open decisions" }
    var suggestChanged: String { isChinese ? "最大变化是什么？" : "What changed most?" }
    var askAcrossMeetings: String { isChinese ? "跨会议提问" : "Ask across your meetings" }
    var resetConversation: String { isChinese ? "重置对话" : "Reset conversation" }
    var settings: String { isChinese ? "设置" : "Settings" }
    var newChat: String { isChinese ? "新对话" : "New chat" }
    var chatHistoryEmpty: String { isChinese ? "开始一个新问题，或点击 ⟲ 查看历史对话。" : "Start a new question, or tap ⟲ to view chat history." }
    var chatHistoryTitle: String { isChinese ? "历史对话" : "Chat History" }
    var chatHistoryDrawerEmpty: String { isChinese ? "暂无历史对话" : "No chat history" }

    // ── ChatView ─────────────────────────────────────────────────

    var processing: String { isChinese ? "处理中..." : "Processing..." }

    // ── Transcript Annotations ────────────────────────────────────

    var annotationAddComment: String { isChinese ? "添加评论" : "Add comment" }
    var annotationTakePhoto: String { isChinese ? "拍照" : "Take photo" }
    var annotationAddImage: String { isChinese ? "添加图片" : "Add image" }
    var annotationCommentPlaceholder: String { isChinese ? "输入评论..." : "Write a comment..." }
    var annotationDeleteImage: String { isChinese ? "删除图片" : "Delete image" }
    var annotationDeleteAll: String { isChinese ? "删除标注" : "Delete annotation" }

    // ── EnhancedNotesView ────────────────────────────────────────

    var noAINotesYet: String { isChinese ? "暂无 AI 笔记。" : "No AI notes yet." }
    var generatingNotesShort: String { isChinese ? "正在生成笔记" : "Generating notes" }

    // ── RecordingControlBar ──────────────────────────────────────

    var recordingTitle: String { isChinese ? "录音" : "Recording" }
    var recorderTitle: String { isChinese ? "录音器" : "Recorder" }
    var ready: String { isChinese ? "准备好了" : "Ready" }
    var resume: String { isChinese ? "继续" : "Resume" }
    var anotherMeetingRecording: String { isChinese ? "另一条会议正在录音" : "Another meeting is recording" }
    var pauseRecording: String { isChinese ? "暂停录音" : "Pause recording" }
    var resumeRecording: String { isChinese ? "继续录音" : "Resume recording" }
    var stopRecording: String { isChinese ? "停止录音" : "Stop recording" }
    var startRecording: String { isChinese ? "开始录音" : "Start recording" }

    // ── AudioPlaybackBar ─────────────────────────────────────────

    var playback: String { isChinese ? "回放" : "Playback" }

    // ── Meeting+Presentation ─────────────────────────────────────

    var notRecorded: String { isChinese ? "未录音" : "Not recorded" }
    var segmentsTranscript: String { isChinese ? "段转写" : " segments" }
    var syncPending: String { isChinese ? "待同步" : "Pending" }
    var syncing: String { isChinese ? "同步中" : "Syncing" }
    var synced: String { isChinese ? "已同步" : "Synced" }
    var syncFailed: String { isChinese ? "同步失败" : "Sync failed" }
    var syncDeleted: String { isChinese ? "待删除" : "Pending delete" }
    var statusIdle: String { isChinese ? "待开始" : "Idle" }
    var statusRecording: String { isChinese ? "录音中" : "Recording" }
    var statusPaused: String { isChinese ? "已暂停" : "Paused" }
    var statusTranscribing: String { isChinese ? "转写中" : "Transcribing" }
    var statusTranscriptionFailed: String { isChinese ? "转写失败" : "Transcription failed" }
    var statusEnded: String { isChinese ? "已结束" : "Ended" }
    var phaseIdle: String { isChinese ? "空闲" : "Idle" }
    var phaseStarting: String { isChinese ? "启动中" : "Starting" }
    var phaseRecording: String { isChinese ? "录音中" : "Recording" }
    var phasePaused: String { isChinese ? "已暂停" : "Paused" }
    var phaseStopping: String { isChinese ? "收尾中" : "Stopping" }
    var asrIdle: String { isChinese ? "未启动" : "Idle" }
    var asrConnecting: String { isChinese ? "连接中" : "Connecting" }
    var asrConnected: String { isChinese ? "已连接" : "Connected" }
    var asrDegraded: String { isChinese ? "已降级" : "Degraded" }
    var asrDisconnected: String { isChinese ? "已断开" : "Disconnected" }
    var today: String { isChinese ? "今天" : "Today" }
    var yesterday: String { isChinese ? "昨天" : "Yesterday" }

    // ── SettingsView ─────────────────────────────────────────────

    var settingsTitle: String { isChinese ? "设置" : "Settings" }
    var languageLabel: String { isChinese ? "语言" : "Language" }
    var about: String { isChinese ? "关于" : "About" }
    var version: String { isChinese ? "版本" : "Version" }
    var serviceMode: String { isChinese ? "服务模式" : "Service mode" }
    var developerMode: String { isChinese ? "开发者模式" : "Developer Mode" }
    var developerDiagnostics: String { isChinese ? "诊断与调试工具" : "Diagnostics and debug tools" }

    // ── DeveloperSettingsView ────────────────────────────────────

    var devSettingsTitle: String { isChinese ? "开发者" : "Developer" }
    var general: String { isChinese ? "通用" : "General" }
    var cloud: String { isChinese ? "云端" : "Cloud" }
    var status: String { isChinese ? "状态" : "Status" }
    var service: String { isChinese ? "服务" : "Service" }
    var recordingQuality: String { isChinese ? "录音" : "Recording" }
    var storage: String { isChinese ? "存储" : "Storage" }
    var onDevice: String { isChinese ? "本机" : "On Device" }
    var refreshStatus: String { isChinese ? "刷新状态" : "Refresh Status" }
    var checking: String { isChinese ? "检查中..." : "Checking..." }
    var useCloudDefault: String { isChinese ? "使用云端默认" : "Use Cloud Default" }
    var backend: String { isChinese ? "后端" : "Backend" }
    var asr: String { "ASR" }
    var ai: String { "AI" }
    var sync: String { isChinese ? "同步" : "Sync" }
    var syncIdleState: String { isChinese ? "空闲" : "Idle" }
    var standby: String { isChinese ? "待命" : "Standby" }

    var liveTranscription: String { "LIVE TRANSCRIPTION" }
    var reconnecting: String { isChinese ? "重连中" : "RECONNECTING" }
    var source: String { isChinese ? "音源" : "Source" }
}

// MARK: - Global Accessor

enum AppStrings {
    /// Thread-safe language storage backed by UserDefaults.
    /// Updated when SettingsStore.appLanguage changes via `syncLanguage()`.
    nonisolated(unsafe) static var currentLanguage: AppLanguage = {
        let raw = UserDefaults.standard.string(forKey: "piedras.settings.appLanguage") ?? ""
        return AppLanguage(rawValue: raw) ?? .chinese
    }()

    static var current: AppStringTable {
        AppStringTable(language: currentLanguage)
    }

    /// Call from SettingsStore.appLanguage.didSet to keep in sync.
    static func syncLanguage(_ lang: AppLanguage) {
        currentLanguage = lang
    }
}
