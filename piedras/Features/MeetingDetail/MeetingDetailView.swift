import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum MeetingDetailMode: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case summary = "AI Notes"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcript: return AppStrings.current.transcript
        case .summary: return AppStrings.current.aiNotes
        }
    }
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
    let accessibilityIdentifier: String
    let action: () -> Void
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            enableInteractivePopGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableInteractivePopGesture()
        }

        private func enableInteractivePopGesture() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore
    @Environment(SettingsStore.self) private var settingsStore

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
    private let actionMenuTopInset: CGFloat = 70
    private let actionMenuHorizontalInset: CGFloat = 24

    var body: some View {
        Group {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                detailScene(meeting: meeting)
            } else {
                ContentUnavailableView(
                    AppStrings.current.meetingNotExist,
                    systemImage: "doc.badge.questionmark",
                    description: Text(AppStrings.current.meetingMayBeDeleted)
                )
            }
        }
        .onDisappear {
            noteSaveTask?.cancel()
            toastTask?.cancel()
        }
        .id(settingsStore.appLanguage)
    }

    private func detailScene(meeting: Meeting) -> some View {
        ZStack(alignment: .top) {
            AppGlassBackdrop()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: selectedMode == .transcript ? 12 : 18) {
                        Color.clear
                            .frame(height: 0)
                            .id(topAnchorID)

                        topBar(meeting: meeting)
                            .zIndex(3)

                        modePicker

                        if let transcriptionStatus = meetingStore.fileTranscriptionStatus(meetingID: meeting.id) {
                            fileTranscriptionStatusView(transcriptionStatus, meetingID: meeting.id)
                        }

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
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.surface)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(AppTheme.ink)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .padding(.top, 72)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsActionMenu)
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .safeAreaInset(edge: .bottom) {
            bottomDock(for: meeting)
        }
        .overlay {
            if showsActionMenu {
                actionMenuOverlay(meeting: meeting)
            }
        }
        .confirmationDialog(AppStrings.current.chooseRecordingMode, isPresented: $showsRecordingModeDialog, titleVisibility: .visible) {
            Button(AppStrings.current.micOnly) {
                Task {
                    await meetingStore.startRecording(meetingID: meeting.id)
                }
            }

            Button(AppStrings.current.audioFilePlusMic) {
                isImportingSourceAudio = true
            }

            Button(AppStrings.current.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.current.chooseRecordingInput)
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
            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: AppStrings.current.back) {
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
                    .accessibilityLabel(meetingStore.isEnhancing(meetingID: meeting.id) ? AppStrings.current.generatingNotes : AppStrings.current.refreshNotes)
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
            }
        }
    }

    private func titleBlock(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(meeting.displayTitle)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(metaLine(for: meeting))
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)

                if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(recordingSessionStore.asrState == .connected ? AppTheme.success : AppTheme.highlight)
                            .frame(width: 6, height: 6)

                        Text(recordingSessionStore.asrState == .connected ? AppStrings.current.liveTranscription : AppStrings.current.reconnecting)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(recordingSessionStore.asrState == .connected ? AppTheme.success : AppTheme.highlight)
                    }
                }
            }
        }
    }

    private func actionMenuOverlay(meeting: Meeting) -> some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color.black.opacity(0.001))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .accessibilityIdentifier("MeetingDetailActionMenuBackdrop")
                .onTapGesture {
                    closeActionMenu()
                }

            actionMenu(meeting: meeting)
                .padding(.top, actionMenuTopInset)
                .padding(.trailing, actionMenuHorizontalInset)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MeetingDetailActionMenu")
    }

    private func documentPage(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if selectedMode == .summary {
                RetroDivider()
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
        HStack(spacing: 0) {
            ForEach(MeetingDetailMode.allCases) { mode in
                Button {
                    closeActionMenu()
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.title.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(selectedMode == mode ? AppTheme.surface : AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selectedMode == mode ? AppTheme.ink : AppTheme.surface)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(mode == .transcript ? "MeetingModeTranscriptTab" : "MeetingModeSummaryTab")
            }
        }
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
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
            Button {
                activeSheet = .chat
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.system(size: 13, weight: .bold))

                    Text(AppStrings.current.chatWithNote)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                )
                .retroHardShadow()
            }
            .buttonStyle(.plain)
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
                DocumentSheetScaffold(title: AppStrings.current.editTitle, onDone: {
                    isTitleEditorFocused = false
                    hideKeyboard()
                    meetingStore.updateTitle(titleDraft, for: meeting)
                    activeSheet = nil
                }) {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField(AppStrings.current.untitledNote, text: $titleDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)
                            .focused($isTitleEditorFocused)
                            .lineLimit(3, reservesSpace: false)

                        RetroDivider()

                        Text(metaLine(for: meeting))
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(AppTheme.subtleInk)
                    }
                    .dismissKeyboardOnTap(isFocused: $isTitleEditorFocused)
                }

            case .rawNotes:
                DocumentSheetScaffold(title: AppStrings.current.myNotes, onDone: {
                    meetingStore.updateNotes(meeting.userNotesPlainText, for: meeting)
                    activeSheet = nil
                }) {
                    NoteEditorView(
                        text: Binding(
                            get: { meeting.userNotesPlainText },
                            set: { scheduleNoteSave($0, for: meeting) }
                        ),
                        showsHeader: false,
                        title: AppStrings.current.notes,
                        placeholder: AppStrings.current.writeHere,
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
                        placeholder: AppStrings.current.writeMarkdownHere,
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
                    AppGlassBackdrop()

                    SecondarySheetPanel(title: AppStrings.current.chatWithNote, onClose: {
                        activeSheet = nil
                    }) {
                        ChatView(meeting: meeting)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .padding(.bottom, 8)
                }
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
                .edgeSwipeToDismiss {
                    activeSheet = nil
                }
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
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 18)

                        Text(item.title)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier(item.accessibilityIdentifier)

                if index < items.count - 1 {
                    RetroDivider()
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: 230, alignment: .leading)
        .padding(.vertical, 8)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
    }

    private func actionItems(meeting: Meeting) -> [MeetingActionItem] {
        switch selectedMode {
        case .summary:
            return [
                MeetingActionItem(title: AppStrings.current.editTitle, systemName: "pencil", accessibilityIdentifier: "MeetingDetailActionEditTitle") {
                    openTitleEditor(for: meeting)
                },
                MeetingActionItem(title: AppStrings.current.editAINotes, systemName: "square.and.pencil", accessibilityIdentifier: "MeetingDetailActionEditAINotes") {
                    closeActionMenu()
                    openEnhancedNotesEditor(for: meeting)
                },
                MeetingActionItem(title: AppStrings.current.showMyNotes, systemName: "square.and.pencil", accessibilityIdentifier: "MeetingDetailActionShowMyNotes") {
                    closeActionMenu()
                    activeSheet = .rawNotes
                },
                MeetingActionItem(title: AppStrings.current.copyNotes, systemName: "doc.on.doc", accessibilityIdentifier: "MeetingDetailActionCopyNotes") {
                    copyCurrentContent(for: meeting)
                },
            ]

        case .transcript:
            var items = [
                MeetingActionItem(title: AppStrings.current.editTitle, systemName: "pencil", accessibilityIdentifier: "MeetingDetailActionEditTitle") {
                    openTitleEditor(for: meeting)
                },
                MeetingActionItem(title: AppStrings.current.viewAINotes, systemName: "sparkles", accessibilityIdentifier: "MeetingDetailActionViewAINotes") {
                    closeActionMenu()
                    selectedMode = .summary
                },
                MeetingActionItem(title: AppStrings.current.showMyNotes, systemName: "square.and.pencil", accessibilityIdentifier: "MeetingDetailActionShowMyNotes") {
                    closeActionMenu()
                    activeSheet = .rawNotes
                },
                MeetingActionItem(title: AppStrings.current.copyTranscript, systemName: "doc.on.doc", accessibilityIdentifier: "MeetingDetailActionCopyTranscript") {
                    copyCurrentContent(for: meeting)
                },
            ]

            if meetingStore.fileTranscriptionStatus(meetingID: meeting.id)?.canRetry == true {
                items.insert(
                    MeetingActionItem(title: AppStrings.current.retryTranscription, systemName: "arrow.clockwise", accessibilityIdentifier: "MeetingDetailActionRetryTranscription") {
                        closeActionMenu()
                        Task {
                            await meetingStore.retryFileTranscription(meetingID: meeting.id)
                        }
                    },
                    at: 1
                )
            }

            return items
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
            toast = AppStrings.current.copiedTranscript
        case .summary:
            content = MarkdownDocumentFormatter.plainText(from: meeting.enhancedNotes)
            toast = AppStrings.current.copiedNotes
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
        let duration = meeting.durationSeconds > 0 ? "\(meeting.durationLabel) \(AppStrings.current.recording_suffix)" : AppStrings.current.notRecordedYet
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

    @ViewBuilder
    private func fileTranscriptionStatusView(_ status: FileTranscriptionStatusSnapshot, meetingID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(status.canRetry ? AppTheme.danger : AppTheme.highlight)
                    .frame(width: 6, height: 6)

                Text(status.displayMessage)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(status.canRetry ? AppTheme.danger : AppTheme.highlight)
            }

            if let errorMessage = status.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button(AppStrings.current.retryTranscription) {
                    Task {
                        await meetingStore.retryFileTranscription(meetingID: meetingID)
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .buttonStyle(.plain)
                .accessibilityIdentifier("MeetingRetryTranscriptionButton")
            }
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
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .frame(width: 40, height: 40)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
            )
    }
}

// MARK: - Retro Sheet Scaffolds

private struct DocumentSheetScaffold<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            SecondarySheetPanel(title: title, onClose: onDone) {
                ScrollView(showsIndicators: false) {
                    content()
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .edgeSwipeToDismiss(onDismiss: onDone)
    }
}

private struct SecondarySheetPanel<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SheetHeaderBar(title: title, onDone: onClose)
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
            )
            .retroHardShadow()
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SecondarySheetPanel")
    }
}

private struct MarkdownEditorSheetScaffold<Content: View>: View {
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            VStack(spacing: 0) {
                Spacer().frame(height: 12)
                SheetActionHeaderBar(onCancel: onCancel, onSave: onSave)

                ScrollView(showsIndicators: false) {
                    content()
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                        .retroHardShadow()
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .edgeSwipeToDismiss(onDismiss: onCancel)
    }
}

private struct SheetHeaderBar: View {
    let title: String
    let onDone: () -> Void

    var body: some View {
        ZStack {
            RetroTitleBar(label: title, showCloseBox: true, onClose: onDone)
        }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("SecondarySheetHeaderBar")
    }
}

private struct SheetActionHeaderBar: View {
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(AppStrings.current.cancel) {
                    onCancel()
                }
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.highlight)
                .accessibilityIdentifier("EnhancedNotesEditorCancelButton")

                Spacer()

                Button(AppStrings.current.save) {
                    onSave()
                }
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("EnhancedNotesEditorSaveButton")
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
            )
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
    }
}

private struct EdgeSwipeDismissModifier: ViewModifier {
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 28)
                    .contentShape(Rectangle())
                    .highPriorityGesture(edgeSwipeGesture)
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: dragOffset)
    }

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard shouldTrack(value) else { return }
                dragOffset = min(max(value.translation.width, 0), 120)
            }
            .onEnded { value in
                defer { dragOffset = 0 }
                guard shouldTrack(value) else { return }

                let projectedWidth = max(value.translation.width, value.predictedEndTranslation.width)
                if projectedWidth > 84 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }
            }
    }

    private func shouldTrack(_ value: DragGesture.Value) -> Bool {
        guard value.startLocation.x <= 28 else { return false }
        guard value.translation.width > 0 else { return false }
        return value.translation.width > abs(value.translation.height)
    }
}

private extension View {
    func edgeSwipeToDismiss(onDismiss: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeDismissModifier(onDismiss: onDismiss))
    }
}
