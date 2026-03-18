import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum MeetingDetailMode: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case summary = "AI Notes"

    var id: String { rawValue }
}

private enum MeetingDetailSheet: String, Identifiable {
    case titleEditor
    case rawNotes
    case enhancedNotesEditor
    case chat

    var id: String { rawValue }
}

private struct MeetingActionItem: Identifiable {
    let id = UUID().uuidString
    let title: String
    let systemName: String
    let action: () -> Void
}

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meetingID: String

    @State private var selectedMode: MeetingDetailMode = .transcript
    @State private var noteSaveTask: Task<Void, Never>?
    @State private var toastTask: Task<Void, Never>?
    @State private var showsRecordingModeDialog = false
    @State private var isImportingSourceAudio = false
    @State private var activeSheet: MeetingDetailSheet?
    @State private var showsActionMenu = false
    @State private var titleDraft = ""
    @State private var enhancedNotesDraft = ""
    @State private var toastMessage: String?
    @FocusState private var isTitleEditorFocused: Bool

    private let topAnchorID = "MeetingDetailTopAnchor"

    var body: some View {
        Group {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                detailScene(meeting: meeting)
            } else {
                ContentUnavailableView(
                    "会议不存在",
                    systemImage: "doc.badge.questionmark",
                    description: Text("这条会议可能已经被删除。")
                )
            }
        }
        .onDisappear {
            noteSaveTask?.cancel()
            toastTask?.cancel()
        }
    }

    private func detailScene(meeting: Meeting) -> some View {
        ZStack(alignment: .top) {
            DocumentBackdrop()

            if showsActionMenu {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeActionMenu()
                    }
            }

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: selectedMode == .transcript ? 12 : 18) {
                        Color.clear
                            .frame(height: 0)
                            .id(topAnchorID)

                        topBar(meeting: meeting)
                            .zIndex(3)

                        modePicker

                        if selectedMode == .summary {
                            titleBlock(meeting: meeting)
                        }

                        documentPage(meeting: meeting)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, contentBottomPadding(for: meeting))
                }
                .onChange(of: selectedMode, initial: false) { _, _ in
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(topAnchorID, anchor: .top)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background {
                        AppGlassSurface(cornerRadius: 18, style: .clear, borderOpacity: 0.18, shadowOpacity: 0.08)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 72)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsActionMenu)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            bottomDock(for: meeting)
        }
        .confirmationDialog("选择录音方式", isPresented: $showsRecordingModeDialog, titleVisibility: .visible) {
            Button("仅麦克风") {
                Task {
                    await meetingStore.startRecording(meetingID: meeting.id)
                }
            }

            Button("音频文件 + 麦克风") {
                isImportingSourceAudio = true
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("选择这次会议的录音输入。")
        }
        .fileImporter(
            isPresented: $isImportingSourceAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleSourceAudioSelection(result, meetingID: meeting.id)
        }
        .sheet(item: $activeSheet) { sheet in
            sheetView(for: sheet)
        }
    }

    private func topBar(meeting: Meeting) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: "返回") {
                closeActionMenu()
                dismiss()
            }
            .accessibilityIdentifier("BackButton")

            Spacer()

            HStack(spacing: 10) {
                if selectedMode == .summary {
                    Button {
                        closeActionMenu()
                        Task {
                            await meetingStore.generateEnhancedNotes(for: meeting.id)
                        }
                    } label: {
                        detailToolLabel(systemName: meetingStore.isEnhancing(meetingID: meeting.id) ? "hourglass" : "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(meetingStore.isEnhancing(meetingID: meeting.id) || !canRefreshSummary(for: meeting))
                    .accessibilityLabel(meetingStore.isEnhancing(meetingID: meeting.id) ? "Generating notes" : "Refresh notes")
                    .accessibilityIdentifier("MeetingRefreshSummaryButton")
                }

                ShareLink(item: sharePayload(for: meeting)) {
                    detailToolLabel(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享")
                .accessibilityIdentifier("MeetingShareButton")

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        showsActionMenu.toggle()
                    }
                } label: {
                    detailToolLabel(systemName: "ellipsis")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("MeetingDetailMoreButton")
                .overlay(alignment: .topTrailing) {
                    if showsActionMenu {
                        actionMenu(meeting: meeting)
                            .offset(y: 54)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    }
                }
            }
        }
    }

    private func titleBlock(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(meeting.displayTitle)
                .font(AppTheme.editorialEmphasisFont(size: 32))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(metaLine(for: meeting))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.subtleInk)

                if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(recordingSessionStore.asrState == .connected ? AppTheme.documentOlive : AppTheme.highlight)
                            .frame(width: 6, height: 6)

                        Text(recordingSessionStore.asrState == .connected ? "Live transcription" : "Reconnecting")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recordingSessionStore.asrState == .connected ? AppTheme.documentOlive : AppTheme.highlight)
                    }
                }
            }
        }
    }

    private func documentPage(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if selectedMode == .summary {
                PaperDivider()
                    .opacity(0.62)
            }

            Group {
                if selectedMode == .transcript {
                    TranscriptView(meeting: meeting)
                } else {
                    EnhancedNotesView(
                        text: meeting.enhancedNotes,
                        meetingID: meeting.id
                    )
                }
            }
            .padding(.top, selectedMode == .summary ? 20 : 0)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: minimumPageHeight, alignment: .topLeading)
    }

    private var modePicker: some View {
        HStack(spacing: 24) {
            ForEach(MeetingDetailMode.allCases) { mode in
                Button {
                    closeActionMenu()
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(mode.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedMode == mode ? AppTheme.ink : AppTheme.subtleInk)

                        Capsule()
                            .fill(selectedMode == mode ? AppTheme.ink : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(mode == .transcript ? "MeetingModeTranscriptTab" : "MeetingModeSummaryTab")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bottomDock(for meeting: Meeting) -> some View {
        if recordingSessionStore.phase != .idle {
            RecordingControlBar(
                meeting: meeting,
                onRequestStartRecording: {
                    showsRecordingModeDialog = true
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        } else if selectedMode == .transcript, let filePath = meeting.audioLocalPath {
            AudioPlaybackBar(filePath: filePath)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
        } else if selectedMode == .summary {
            AppGlassCapsuleButton(prominent: false) {
                activeSheet = .chat
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Chat with note")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(AppTheme.ink)
            }
            .accessibilityIdentifier("MeetingAskButton")
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: MeetingDetailSheet) -> some View {
        if let meeting = meetingStore.meeting(withID: meetingID) {
            switch sheet {
            case .titleEditor:
                DocumentSheetScaffold(title: "Edit title", onDone: {
                    isTitleEditorFocused = false
                    hideKeyboard()
                    meetingStore.updateTitle(titleDraft, for: meeting)
                    activeSheet = nil
                }) {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("Untitled note", text: $titleDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(AppTheme.editorialEmphasisFont(size: 34))
                            .foregroundStyle(AppTheme.ink)
                            .focused($isTitleEditorFocused)
                            .lineLimit(3, reservesSpace: false)

                        PaperDivider()
                            .opacity(0.56)

                        Text(metaLine(for: meeting))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.subtleInk)
                    }
                    .dismissKeyboardOnTap(isFocused: $isTitleEditorFocused)
                }

            case .rawNotes:
                DocumentSheetScaffold(title: "My notes", onDone: {
                    meetingStore.updateNotes(meeting.userNotesPlainText, for: meeting)
                    activeSheet = nil
                }) {
                    NoteEditorView(
                        text: Binding(
                            get: { meeting.userNotesPlainText },
                            set: { scheduleNoteSave($0, for: meeting) }
                        ),
                        showsHeader: false,
                        title: "Notes",
                        placeholder: "Write here.",
                        minHeight: 520
                    )
                }

            case .enhancedNotesEditor:
                MarkdownEditorSheetScaffold(
                    onCancel: {
                        activeSheet = nil
                    },
                    onSave: {
                        saveEnhancedNotesDraft(for: meeting)
                    }
                ) {
                    EditorialDocumentEditor(
                        text: $enhancedNotesDraft,
                        placeholder: "Write markdown here.",
                        minHeight: 520,
                        fontSize: 16,
                        lineSpacing: 6,
                        autocapitalization: .none,
                        usesSmartDashes: false,
                        usesSmartQuotes: false,
                        accessibilityIdentifier: "EnhancedNotesMarkdownEditor"
                    )
                }

            case .chat:
                ZStack {
                    DocumentBackdrop()

                    VStack(spacing: 0) {
                        SheetHeaderBar(title: "Chat with note") {
                            activeSheet = nil
                        }

                        ChatView(meeting: meeting)
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }
                }
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
            }
        } else {
            EmptyView()
        }
    }

    private func actionMenu(meeting: Meeting) -> some View {
        let items = actionItems(meeting: meeting)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 18)

                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.ink)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)

                if index < items.count - 1 {
                    Divider()
                        .overlay(AppTheme.documentHairline.opacity(0.45))
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: 230, alignment: .leading)
        .padding(.vertical, 8)
        .background {
            AppGlassSurface(cornerRadius: 24, style: .clear, borderOpacity: 0.20, shadowOpacity: 0.12)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppTheme.documentPaper.opacity(0.90))
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func actionItems(meeting: Meeting) -> [MeetingActionItem] {
        switch selectedMode {
        case .summary:
            return [
                MeetingActionItem(title: "Edit title", systemName: "pencil") {
                    openTitleEditor(for: meeting)
                },
                MeetingActionItem(title: "Edit AI notes", systemName: "square.and.pencil") {
                    closeActionMenu()
                    openEnhancedNotesEditor(for: meeting)
                },
                MeetingActionItem(title: "Show my notes", systemName: "square.and.pencil") {
                    closeActionMenu()
                    activeSheet = .rawNotes
                },
                MeetingActionItem(title: "Copy notes", systemName: "doc.on.doc") {
                    copyCurrentContent(for: meeting)
                },
            ]

        case .transcript:
            return [
                MeetingActionItem(title: "Edit title", systemName: "pencil") {
                    openTitleEditor(for: meeting)
                },
                MeetingActionItem(title: "View AI notes", systemName: "sparkles") {
                    closeActionMenu()
                    selectedMode = .summary
                },
                MeetingActionItem(title: "Show my notes", systemName: "square.and.pencil") {
                    closeActionMenu()
                    activeSheet = .rawNotes
                },
                MeetingActionItem(title: "Copy transcript", systemName: "doc.on.doc") {
                    copyCurrentContent(for: meeting)
                },
            ]
        }
    }

    private var minimumPageHeight: CGFloat {
        max(560, UIScreen.main.bounds.height * 0.66)
    }

    private func openTitleEditor(for meeting: Meeting) {
        titleDraft = meeting.title
        closeActionMenu()
        activeSheet = .titleEditor
    }

    private func openEnhancedNotesEditor(for meeting: Meeting) {
        enhancedNotesDraft = meeting.enhancedNotes
        closeActionMenu()
        activeSheet = .enhancedNotesEditor
    }

    private func sharePayload(for meeting: Meeting) -> String {
        let body: String

        switch selectedMode {
        case .transcript:
            body = meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .summary:
            body = MarkdownDocumentFormatter.plainText(from: meeting.enhancedNotes)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if body.isEmpty {
            return meeting.displayTitle
        }

        return "\(meeting.displayTitle)\n\n\(body)"
    }

    private func copyCurrentContent(for meeting: Meeting) {
        let content: String
        let toast: String

        switch selectedMode {
        case .transcript:
            content = meeting.transcriptText
            toast = "Copied transcript"
        case .summary:
            content = MarkdownDocumentFormatter.plainText(from: meeting.enhancedNotes)
            toast = "Copied notes"
        }

        UIPasteboard.general.string = content.trimmingCharacters(in: .whitespacesAndNewlines)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        closeActionMenu()
        showToast(toast)
    }

    private func closeActionMenu() {
        showsActionMenu = false
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            toastMessage = message
        }

        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                toastMessage = nil
            }
        }
    }

    private func scheduleNoteSave(_ newValue: String, for meeting: Meeting) {
        noteSaveTask?.cancel()
        meeting.userNotesPlainText = newValue
        noteSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            meetingStore.updateNotes(newValue, for: meeting)
        }
    }

    private func saveEnhancedNotesDraft(for meeting: Meeting) {
        let normalized = enhancedNotesDraft
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        meetingStore.updateEnhancedNotes(normalized, for: meeting)
        activeSheet = nil
    }

    private func canRefreshSummary(for meeting: Meeting) -> Bool {
        !meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func metaLine(for meeting: Meeting) -> String {
        let date = meeting.date.formatted(.dateTime.month(.wide).day().year())
        let duration = meeting.durationSeconds > 0 ? "\(meeting.durationLabel) recording" : "Not recorded yet"
        return "\(date) · \(duration)"
    }

    private func contentBottomPadding(for meeting: Meeting) -> CGFloat {
        if recordingSessionStore.phase != .idle {
            return 210
        }

        switch selectedMode {
        case .transcript:
            return meeting.audioLocalPath == nil ? 64 : 176
        case .summary:
            return 132
        }
    }

    private func handleSourceAudioSelection(_ result: Result<[URL], Error>, meetingID: String) {
        switch result {
        case let .success(urls):
            guard let sourceURL = urls.first else { return }
            let displayName = sourceURL.deletingPathExtension().lastPathComponent
            Task {
                await meetingStore.startRecording(
                    meetingID: meetingID,
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

    private func detailToolLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .frame(width: 40, height: 40)
            .background {
                AppGlassSurface(cornerRadius: 20, style: .clear, borderOpacity: 0.18, shadowOpacity: 0.08)
                    .clipShape(Circle())
            }
    }
}

private struct DocumentSheetScaffold<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            DocumentBackdrop()

            VStack(spacing: 0) {
                SheetHeaderBar(title: title, onDone: onDone)

                ScrollView(showsIndicators: false) {
                    content()
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            PaperSurface(
                                cornerRadius: 34,
                                fill: AppTheme.documentPaper,
                                border: AppTheme.documentHairline,
                                shadowOpacity: 0.05
                            )
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
    }
}

private struct MarkdownEditorSheetScaffold<Content: View>: View {
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            DocumentBackdrop()

            VStack(spacing: 0) {
                SheetActionHeaderBar(onCancel: onCancel, onSave: onSave)

                ScrollView(showsIndicators: false) {
                    content()
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            PaperSurface(
                                cornerRadius: 34,
                                fill: AppTheme.documentPaper,
                                border: AppTheme.documentHairline,
                                shadowOpacity: 0.05
                            )
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
    }
}

private struct SheetHeaderBar: View {
    let title: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(AppTheme.subtleInk.opacity(0.28))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            HStack {
                Color.clear
                    .frame(width: 54, height: 38)

                Spacer()

                Text(title)
                    .font(AppTheme.editorialEmphasisFont(size: 18))
                    .foregroundStyle(AppTheme.ink)

                Spacer()

                Button("Done") {
                    onDone()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background {
                    AppGlassSurface(cornerRadius: 19, style: .clear, borderOpacity: 0.18, shadowOpacity: 0.08)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
        }
    }
}

private struct SheetActionHeaderBar: View {
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(AppTheme.subtleInk.opacity(0.28))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.red)
                .accessibilityIdentifier("EnhancedNotesEditorCancelButton")

                Spacer()

                Button("Save") {
                    onSave()
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("EnhancedNotesEditorSaveButton")
            }
            .padding(.horizontal, 28)
            .frame(height: 58)
            .background {
                AppGlassSurface(cornerRadius: 29, style: .clear, borderOpacity: 0.22, shadowOpacity: 0.10)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
        }
    }
}
