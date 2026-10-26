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

    var appTitle: String { "Piedras" }
    var noNotesYet: String { isChinese ? "还没有笔记" : "No notes yet" }
    var tapMicToCapture: String { isChinese ? "点击麦克风开始你的第一条笔记。" : "Tap the mic to capture your first note." }
    var chatWithNotes: String { isChinese ? "与笔记对话" : "Chat with notes" }
    var uploadAudio: String { isChinese ? "上传音频" : "Upload audio" }
    var newRecording: String { isChinese ? "新录音" : "New recording" }
    var stop: String { isChinese ? "停止" : "Stop" }
    var deleteAction: String { isChinese ? "删除" : "Delete" }
    var deleteNoteAction: String { isChinese ? "删除笔记" : "Delete note" }
    var moveNoteAction: String { isChinese ? "移动" : "Move" }
    var restoreNoteAction: String { isChinese ? "恢复" : "Restore" }
    var permanentlyDeleteNoteAction: String { isChinese ? "彻底删除" : "Delete Permanently" }
    var folders: String { isChinese ? "文件夹" : "Folders" }
    var foldersComingSoon: String { isChinese ? "文件夹功能即将上线" : "Folders are coming soon" }
    var defaultFolderName: String { isChinese ? "默认文件栏" : "Default Folder" }
    var recentlyDeletedFolderName: String { isChinese ? "最近删除" : "Recently Deleted" }
    var folderDrawerTitle: String { isChinese ? "文件夹" : "Folders" }
    var newFolder: String { isChinese ? "新建文件夹" : "New Folder" }
    var createFolderAction: String { isChinese ? "创建" : "Create" }
    var newFolderPromptTitle: String { isChinese ? "新建文件夹" : "Create Folder" }
    var newFolderPlaceholder: String { isChinese ? "输入文件夹名称" : "Enter folder name" }
    var newFolderNameRequired: String { isChinese ? "请输入文件夹名称。" : "Enter a folder name." }
    var folderEmptyState: String { isChinese ? "当前只有默认文件夹。" : "Only the default folder is available." }
    var deleteFolderAction: String { isChinese ? "删除文件夹" : "Delete Folder" }
    var deleteFolderMessage: String { isChinese ? "删除后，其中的笔记会移回默认文件夹。" : "Deleting this folder moves its notes back to the default folder." }
    var moveNotePromptTitle: String { isChinese ? "选择目标文件夹" : "Select Folder" }

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
    var recordingNotePromptTitle: String { isChinese ? "在此书写" : "Write here" }
    var recordingNotePromptHint: String { isChinese ? "点击开始记录笔记" : "Tap to start taking notes" }
    var renameTitlePrompt: String { isChinese ? "输入新的笔记标题" : "Enter a new title for the note" }
    var meetingTypeLabel: String { isChinese ? "笔记类型" : "Note type" }
    var meetingTypeHint: String { isChinese ? "影响 AI 笔记结构与重点" : "Shapes AI note structure and emphasis" }
    var dismissKeyboard: String { isChinese ? "收起键盘" : "Hide keyboard" }
    var notesTeaserEmpty: String { isChinese ? "记下想法，会并入 AI 笔记" : "Capture thoughts to blend into AI notes" }
    var notesTeaserContinue: String { isChinese ? "继续记录你的想法" : "Keep writing your thoughts" }
    var notesMergeHint: String { isChinese ? "这些随手笔记会在下次生成或刷新 AI 笔记时并入。" : "These notes will be blended into AI Notes the next time you generate or refresh them." }
    var notRecordedYet: String { isChinese ? "未录音" : "Not recorded yet" }
    var recording_suffix: String { isChinese ? "录音" : "recording" }
    var back: String { isChinese ? "返回" : "Back" }
    var share: String { isChinese ? "分享" : "Share" }
    var attachments: String { isChinese ? "附件" : "Attachments" }
    var noteAttachmentsTitle: String { isChinese ? "资料区" : "Attached" }
    var noteAttachmentsHint: String { isChinese ? "图片文字会在刷新 AI 笔记时并入上下文。" : "Image text will be added to AI Notes the next time you refresh." }
    var generatingNotes: String { isChinese ? "正在生成笔记" : "Generating notes" }
    var refreshNotes: String { isChinese ? "刷新笔记" : "Refresh notes" }
    var regenerateNotes: String { isChinese ? "重新生成笔记" : "Regenerate notes" }
    var generatingUpdatedNotesHint: String { isChinese ? "新的笔记正在生成中" : "A new version of the notes is being generated" }
    var cannotRefreshNotesWithoutMaterial: String { isChinese ? "当前没有可用于生成 AI 笔记的内容。" : "There is not enough material to refresh AI notes right now." }
    var imageTextRefreshHint: String { isChinese ? "图片文字已更新，刷新 AI 笔记后会纳入这些新增上下文。" : "Image text was updated. Refresh AI Notes to include the new context." }
    var cancel: String { isChinese ? "取消" : "Cancel" }
    var save: String { isChinese ? "保存" : "Save" }
    var notes: String { isChinese ? "笔记" : "Notes" }
    var preparingImportedAudio: String { isChinese ? "正在准备音频..." : "Preparing audio..." }
    var connectingASR: String { isChinese ? "正在连接 ASR..." : "Connecting ASR..." }
    var finalizingTranscription: String { isChinese ? "正在整理转写..." : "Finalizing transcript..." }
    var audioTranscriptionFailed: String { isChinese ? "文件转写失败" : "Audio transcription failed" }
    var noSpeechDetectedInAudio: String { isChinese ? "这段音频里没有检测到可转写的人声。" : "No speech was detected in this audio." }
    var audioFileNeedsReexport: String { isChinese ? "当前音频暂时无法稳定解析，请重新导出为 m4a、mp3 或 wav 后重试。" : "This audio could not be parsed reliably. Please re-export it as m4a, mp3, or wav and try again." }
    var audioTranscriptionConnectionIssue: String { isChinese ? "当前网络或转写连接不稳定，请稍后重试。" : "The network or transcription connection is unstable. Please try again shortly." }
    var audioTranscriptionServiceUnavailable: String { isChinese ? "当前转写服务暂时不可用，请稍后重试。" : "The transcription service is temporarily unavailable. Please try again shortly." }
    var audioPlaybackFailed: String { isChinese ? "当前音频暂时无法播放，请重试或重新导出为 m4a、mp3 或 wav。" : "This audio cannot be played right now. Please try again or re-export it as m4a, mp3, or wav." }
    var speakerDiarizationFailed: String { isChinese ? "说话人整理失败" : "Speaker separation failed" }
    var retryTranscription: String { isChinese ? "重新转写" : "Retry transcription" }
    var fileTranscriptionInterrupted: String { isChinese ? "应用中断了上次文件转写，请重新转写。" : "The previous file transcription was interrupted. Please retry." }
    var renameSpeaker: String { isChinese ? "重命名说话人" : "Rename speaker" }
    var renameSpeakerPrompt: String { isChinese ? "输入名字；留空会恢复默认标签。" : "Enter a name; leave it blank to restore the default label." }
    var speakerNamePlaceholder: String { isChinese ? "说话人名称" : "Speaker name" }

    func meetingTypeName(_ type: MeetingTypeOption) -> String {
        switch type {
        case .general:
            return isChinese ? "通用" : "General"
        case .interview:
            return isChinese ? "访谈" : "Interview"
        case .speech:
            return isChinese ? "演讲" : "Talk"
        case .brainstorming:
            return isChinese ? "头脑风暴" : "Brainstorm"
        case .weekly:
            return isChinese ? "项目周会" : "Project weekly"
        case .requirementsReview:
            return isChinese ? "需求评审" : "Requirement review"
        case .sales:
            return isChinese ? "销售沟通" : "Sales sync"
        case .interviewReview:
            return isChinese ? "面试复盘" : "Interview recap"
        }
    }

    func speakerLabel(_ index: Int) -> String {
        let normalized = max(index, 1)
        return isChinese ? "说话人 \(normalized)" : "Speaker \(normalized)"
    }

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
    var userNotesSource: String { isChinese ? "用户笔记" : "User notes" }
    var commentSource: String { isChinese ? "评论" : "Comment" }
    var imageTextSource: String { isChinese ? "图片文字" : "Image text" }

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
    var regenerateAnswer: String { isChinese ? "重新生成回答" : "Regenerate answer" }
    var chatHistoryEmpty: String { isChinese ? "开始一个新问题，或点击 ⟲ 查看历史对话。" : "Start a new question, or tap ⟲ to view chat history." }
    var chatHistoryTitle: String { isChinese ? "历史对话" : "Chat History" }
    var chatHistoryDrawerEmpty: String { isChinese ? "暂无历史对话" : "No chat history" }

    func chatHistoryCountSummary(_ count: Int) -> String {
        let normalizedCount = max(count, 0)

        if normalizedCount > 9 {
            return isChinese ? "9 条以上" : "9 or more chats"
        }

        if isChinese {
            return "\(normalizedCount) 条"
        }

        let noun = normalizedCount == 1 ? "chat" : "chats"
        return "\(normalizedCount) \(noun)"
    }

    func chatHistoryButtonAccessibilityLabel(baseLabel: String, count: Int) -> String {
        let separator = isChinese ? "，" : ", "
        return "\(baseLabel)\(separator)\(chatHistoryCountSummary(count))"
    }

    // ── ChatView ─────────────────────────────────────────────────

    var processing: String { isChinese ? "处理中..." : "Processing..." }
    var meetingChatScopeHint: String { isChinese ? "仅针对当前笔记提问" : "Ask about this note only" }
    var meetingChatEmptyPrompt: String { isChinese ? "从当前笔记中提问。" : "Ask from this note." }
    var meetingChatSuggestSummarize: String { isChinese ? "总结这条笔记" : "Summarize this note" }
    var meetingChatSuggestNextSteps: String { isChinese ? "下一步是什么？" : "What are the next steps?" }
    var meetingChatComposerPlaceholder: String { isChinese ? "问这条笔记里的细节、决定或下一步…" : "Ask about details, decisions, or next steps in this note…" }

    // ── Transcript Annotations ────────────────────────────────────

    var annotationAddComment: String { isChinese ? "添加评论" : "Add comment" }
    var annotationTakePhoto: String { isChinese ? "拍照" : "Take photo" }
    var annotationAddImage: String { isChinese ? "添加图片" : "Add image" }
    var annotationCommentPlaceholder: String { isChinese ? "输入评论..." : "Write a comment..." }
    var annotationDeleteImage: String { isChinese ? "删除图片" : "Delete image" }
    var annotationDeleteAll: String { isChinese ? "删除标注" : "Delete annotation" }
    var cameraUnavailable: String { isChinese ? "当前设备不支持拍照。" : "Camera is unavailable on this device." }

    func noteAttachmentLimitReached(_ limit: Int) -> String {
        isChinese ? "最多只能添加 \(limit) 张图片。" : "You can attach up to \(limit) images."
    }

    func noteAttachmentsAdded(_ count: Int) -> String {
        let normalized = max(count, 0)
        return isChinese ? "已添加 \(normalized) 张图片。" : "Added \(normalized) images."
    }

    func duplicateNoteAttachmentSkipped() -> String {
        isChinese ? "这张照片已添加过。" : "That photo has already been added."
    }

    func noteAttachmentsSkippedDuplicates(_ duplicateCount: Int) -> String {
        let duplicates = max(duplicateCount, 0)
        return isChinese
            ? "跳过 \(duplicates) 张重复图片。"
            : "Skipped \(duplicates) duplicate images."
    }

    func noteAttachmentsAddedSkippingDuplicates(addedCount: Int, duplicateCount: Int) -> String {
        let added = max(addedCount, 0)
        let duplicates = max(duplicateCount, 0)
        return isChinese
            ? "已添加 \(added) 张，跳过 \(duplicates) 张重复图片。"
            : "Added \(added), skipped \(duplicates) duplicate images."
    }

    // ── EnhancedNotesView ────────────────────────────────────────

    var noAINotesYet: String { isChinese ? "暂无 AI 笔记。" : "No AI notes yet." }
    var generatingNotesShort: String { isChinese ? "正在生成笔记" : "Generating notes" }
    var textAINotesVersion: String { isChinese ? "文本版 AI 笔记" : "Transcript AI Notes" }
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
    var transcriptRecordingNotice: String { isChinese ? "正在录音，结束后可回放原始音频" : "Recording in progress. Original audio will be available after stop." }

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
    var accountSectionTitle: String { isChinese ? "账号" : "Account" }
    var languageLabel: String { isChinese ? "语言" : "Language" }
    var about: String { isChinese ? "关于" : "About" }
    var version: String { isChinese ? "版本" : "Version" }
    var serviceMode: String { isChinese ? "服务模式" : "Service mode" }
    var developerMode: String { isChinese ? "开发者模式" : "Developer Mode" }
    var developerDiagnostics: String { isChinese ? "诊断与调试工具" : "Diagnostics and debug tools" }
    var logoutAction: String { isChinese ? "退出登录" : "Log out" }

    // ── AuthView ────────────────────────────────────────────────

    var authSubtitle: String { isChinese ? "用邮箱账号安全保存你的录音、转写和笔记。" : "Use your email account to securely keep recordings, transcripts, and notes." }
    var authLoginTab: String { isChinese ? "登录" : "Sign In" }
    var authRegisterTab: String { isChinese ? "注册" : "Register" }
    var authSingleStepAction: String { isChinese ? "进入" : "Continue" }
    var authSingleStepHint: String { isChinese ? "未注册账号会自动创建并登录" : "If this email is new, we'll create the account and sign you in." }
    var authPasswordLoginTab: String { isChinese ? "密码登录" : "Password" }
    var authCodeLoginTab: String { isChinese ? "验证码登录" : "One-time code" }
    var authLoginAction: String { isChinese ? "登录并进入" : "Sign In" }
    var authOTPLoginAction: String { isChinese ? "验证码登录" : "Sign in with code" }
    var authRegisterAction: String { isChinese ? "注册并进入" : "Register and continue" }
    var authSendCodeAction: String { isChinese ? "发送验证码" : "Send code" }
    var authResendCodeAction: String { isChinese ? "重新发送验证码" : "Resend code" }
    var authEmailLabel: String { isChinese ? "邮箱" : "Email" }
    var authPasswordLabel: String { isChinese ? "密码" : "Password" }
    var authSetPasswordLabel: String { isChinese ? "设置密码（可选）" : "Set password (optional)" }
    var authOneTimeCodeLabel: String { isChinese ? "邮箱验证码" : "Email code" }
    var authDisplayNameLabel: String { isChinese ? "昵称（可选）" : "Display name (optional)" }
    var authWorkspaceLabel: String { isChinese ? "工作区" : "Workspace" }
    var authPasswordPlaceholder: String { isChinese ? "至少 8 位" : "At least 8 characters" }
    var authOneTimeCodePlaceholder: String { isChinese ? "输入 6 位验证码" : "Enter the 6-digit code" }
    var authDisplayNamePlaceholder: String { isChinese ? "用于内部识别" : "Shown internally" }
    var authRestoringSession: String { isChinese ? "正在恢复登录状态..." : "Restoring session..." }
    var authForgotPasswordAction: String { isChinese ? "忘记密码" : "Forgot password" }
    var authResendVerificationAction: String { isChinese ? "重新发送验证邮件" : "Resend verification email" }
    var authContinueAction: String { isChinese ? "继续" : "Continue" }
    var authSkipPasswordSetupAction: String { isChinese ? "先跳过" : "Skip for now" }
    var authPasswordSetupTitle: String { isChinese ? "账号已创建" : "Account created" }
    var authPasswordSetupMessage: String { isChinese ? "现在可以补一个密码，之后登录更方便；也可以先跳过，继续使用邮箱验证码登录。" : "You can add a password now for easier sign-in later, or skip and keep using one-time codes." }
    var authVerificationPendingTitle: String { isChinese ? "等待邮箱验证" : "Email verification pending" }
    var authResetHint: String { isChinese ? "支持邮箱验证码登录，也支持密码登录和自助重置密码。" : "Use either one-time codes or passwords. Self-service password reset is also available." }
    var authSwitchHint: String { isChinese ? "切换账号前请先退出当前账号。" : "Log out first before switching accounts." }
    var authForceLogoutTitle: String { isChinese ? "放弃未同步数据并退出？" : "Discard unsynced data and log out?" }
    var authForceLogoutAction: String { isChinese ? "强制退出" : "Force logout" }
    var authForceLogoutMessage: String { isChinese ? "本地还有未同步数据，强制退出会直接清空这些本地内容。" : "There is unsynced local data. Force logout will remove it from this device." }
    var authOTPRegisterMessage: String { isChinese ? "输入邮箱后发送验证码，验证成功后会直接注册并进入。" : "Enter your email, get a code, and you will register and continue right after verification." }
    var authOTPLoginMessage: String { isChinese ? "输入邮箱后发送验证码，无需密码也能登录。" : "Send a one-time code to your email and sign in without a password." }
    var authPasswordLoginMessage: String { isChinese ? "使用邮箱和密码登录你的账号。" : "Use your email and password to sign in." }

    func authVerificationPendingMessage(email: String?) -> String {
        let fallback = isChinese ? "你的邮箱" : "your email"
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let target = normalizedEmail.isEmpty ? fallback : normalizedEmail
        return isChinese
            ? "验证邮件已发送到 \(target)。完成验证后再回来登录。"
            : "We sent a verification email to \(target). Finish verification and then sign in."
    }

    func authOTPSentMessage(email: String?, intent: EmailOTPIntent) -> String {
        let fallback = isChinese ? "你的邮箱" : "your email"
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let target = normalizedEmail.isEmpty ? fallback : normalizedEmail

        if isChinese {
            return intent == .login
                ? "验证码已发送到 \(target)，输入后即可登录。"
                : "验证码已发送到 \(target)，输入后即可完成注册。"
        }

        return intent == .login
            ? "We sent a sign-in code to \(target). Enter it to continue."
            : "We sent a sign-up code to \(target). Enter it to finish registration."
    }

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
    var recentSync: String { isChinese ? "最近同步" : "Recent sync" }
    var syncIdleState: String { isChinese ? "空闲" : "Idle" }
    var standby: String { isChinese ? "待命" : "Standby" }
    var syncRepairAction: String { isChinese ? "立即修复云端状态" : "Repair Cloud State" }
    var syncDetail: String { isChinese ? "同步详情" : "Sync detail" }
    var lastFailure: String { isChinese ? "最近失败" : "Last failure" }
    var nextRetry: String { isChinese ? "下次重试" : "Next retry" }
    var lastSuccess: String { isChinese ? "最近成功" : "Last success" }
    var notAvailableShort: String { isChinese ? "暂无" : "N/A" }

    var liveTranscription: String { "LIVE TRANSCRIPTION" }
    var reconnecting: String { isChinese ? "重连中" : "RECONNECTING" }
    var backgroundTranscribing: String { isChinese ? "后台转写中" : "BACKGROUND TRANSCRIBING" }
    var finalizingBackgroundTranscript: String { isChinese ? "后台转写收尾中" : "FINALIZING BACKGROUND TRANSCRIPT" }
    var backgroundTranscriptRepairOnStop: String { isChinese ? "停止后修复" : "REPAIR ON STOP" }
    var source: String { isChinese ? "音源" : "Source" }
    var backgroundRecordingBestEffort: String { isChinese ? "应用已切到后台，录音会继续；实时转写会尽量保持。" : "The app is in the background. Recording continues and live transcription will continue when possible." }
    var backgroundTranscriptWillCatchUp: String { isChinese ? "后台实时转写已中断，回到前台后会自动补齐缺失片段。" : "Background live transcription was interrupted. Missing transcript will be filled in when you return." }
    var backfillingBackgroundTranscript: String { isChinese ? "正在补齐后台片段的转写…" : "Filling in transcript captured in the background…" }
    var backgroundTranscriptPendingRepair: String { isChinese ? "后台片段暂未补齐，停止录音后会自动修复。" : "Background transcript is still incomplete. It will be repaired when recording stops." }
    var recordingInterruptedNeedsResume: String { isChinese ? "录音在后台被系统打断，请返回应用后继续。" : "Recording was interrupted in the background. Return to the app to continue." }
    var liveTranscriptHint: String { isChinese ? "长按录音条查看完整实时转写" : "Long press the recorder to view the full live transcript" }
    var liveTranscriptTapHint: String { isChinese ? "点击查看实时转写" : "Tap to view live transcript" }
    var transcriptPausedHint: String { isChinese ? "转写已暂停" : "Transcription paused" }
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
