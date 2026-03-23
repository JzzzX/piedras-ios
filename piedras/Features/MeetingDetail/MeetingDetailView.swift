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
    @State private var showsNotesDrawer = false
    @State private var showsTitleRenameDialog = false
    @State private var activeSheet: MeetingDetailSheet?
    @State private var showsActionMenu = false
    @State private var titleDraft = ""
    @State private var currentTitleOverride: String?
    @State private var currentNotesOverride: String?
    @State private var enhancedNotesDraft = ""
    @State private var toastMessage: String?
    @FocusState private var isTitleRenameFocused: Bool

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
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
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
            bottomStack(for: meeting)
        }
        .overlay {
            if showsActionMenu {
                actionMenuOverlay(meeting: meeting)
            }
        }
        .overlay {
            if showsTitleRenameDialog {
                titleRenameOverlay(meeting: meeting)
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
        .sheet(isPresented: $showsNotesDrawer) {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                MeetingNotesDrawer(
                    meeting: meeting,
                    initialText: currentNotesText(for: meeting),
                    onClose: {
                        closeNotesDrawer(for: meeting)
                    },
                    onTextChange: { newValue in
                        scheduleNoteSave(newValue, for: meeting)
                    }
                )
            }
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
        Button {
            openTitleRenameDialog(for: meeting)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Text(displayTitle(for: meeting))
                        .font(AppTheme.bodyFont(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("MeetingDetailTitleText")

                    Spacer(minLength: 0)

                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.subtleInk)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(metaLine(for: meeting))
                        .font(AppTheme.dataFont(size: 14))
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("MeetingDetailTitleButton")
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
                ThinDivider()
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
                    Text(mode.title)
                        .font(AppTheme.bodyFont(size: 13, weight: .semibold))
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
    private func bottomStack(for meeting: Meeting) -> some View {
        VStack(spacing: 10) {
            if selectedMode == .transcript {
                notesTeaser()
                    .padding(.horizontal, 20)
            }

            bottomDock(for: meeting)
        }
        .padding(.top, selectedMode == .transcript ? 8 : 0)
        .padding(.bottom, 12)
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
        } else if selectedMode == .transcript, let filePath = meeting.audioLocalPath {
            AudioPlaybackBar(filePath: filePath)
                .padding(.horizontal, 20)
        } else if selectedMode == .summary {
            Button {
                activeSheet = .chat
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.system(size: 13, weight: .bold))

                    Text(AppStrings.current.chatWithNote)
                        .font(AppTheme.bodyFont(size: 15, weight: .semibold))
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
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: MeetingDetailSheet) -> some View {
        if let meeting = meetingStore.meeting(withID: meetingID) {
            switch sheet {
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
                            .font(AppTheme.bodyFont(size: 14, weight: .semibold))
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
                    ThinDivider()
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
                MeetingActionItem(title: AppStrings.current.editAINotes, systemName: "square.and.pencil", accessibilityIdentifier: "MeetingDetailActionEditAINotes") {
                    closeActionMenu()
                    openEnhancedNotesEditor(for: meeting)
                },
                MeetingActionItem(title: AppStrings.current.copyNotes, systemName: "doc.on.doc", accessibilityIdentifier: "MeetingDetailActionCopyNotes") {
                    copyCurrentContent(for: meeting)
                },
            ]

        case .transcript:
            var items = [
                MeetingActionItem(title: AppStrings.current.viewAINotes, systemName: "sparkles", accessibilityIdentifier: "MeetingDetailActionViewAINotes") {
                    closeActionMenu()
                    selectedMode = .summary
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

    private func openTitleRenameDialog(for meeting: Meeting) {
        titleDraft = currentRawTitle(for: meeting)
        closeActionMenu()
        showsTitleRenameDialog = true
        Task { @MainActor in
            isTitleRenameFocused = true
        }
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
        currentNotesOverride = newValue
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

    private func closeTitleRenameDialog() {
        isTitleRenameFocused = false
        hideKeyboard()
        showsTitleRenameDialog = false
    }

    private func commitTitleRename(for meeting: Meeting) {
        let normalized = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTitleOverride = normalized
        meetingStore.updateTitle(normalized, for: meeting)
        closeTitleRenameDialog()
    }

    private func closeNotesDrawer(for meeting: Meeting) {
        noteSaveTask?.cancel()
        let currentNotes = currentNotesText(for: meeting)
        meetingStore.updateNotes(currentNotes, for: meeting)
        showsNotesDrawer = false
    }

    private func metaLine(for meeting: Meeting) -> String {
        let date = meeting.date.formatted(.dateTime.month(.wide).day().year())
        let duration = meeting.durationSeconds > 0 ? "\(meeting.durationLabel) \(AppStrings.current.recording_suffix)" : AppStrings.current.notRecordedYet
        return "\(date) · \(duration)"
    }

    private func contentBottomPadding(for meeting: Meeting) -> CGFloat {
        if recordingSessionStore.phase != .idle {
            return selectedMode == .transcript ? 296 : 210
        }

        switch selectedMode {
        case .transcript:
            return meeting.audioLocalPath == nil ? 152 : 264
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
                    .font(AppTheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(status.canRetry ? AppTheme.danger : AppTheme.highlight)
            }

            if let errorMessage = status.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button(AppStrings.current.retryTranscription) {
                    Task {
                        await meetingStore.retryFileTranscription(meetingID: meetingID)
                    }
                }
                .font(AppTheme.bodyFont(size: 12, weight: .semibold))
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

    private func notesTeaser() -> some View {
        Button {
            closeActionMenu()
            showsNotesDrawer = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(width: 22, height: 22)

                Text(AppStrings.current.myNotes)
                    .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.highlight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(AppTheme.surface)
            .softCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("MeetingTranscriptNotesTeaser")
    }

    private func displayTitle(for meeting: Meeting) -> String {
        let trimmed = currentRawTitle(for: meeting).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppStrings.current.untitledMeeting : trimmed
    }

    private func currentRawTitle(for meeting: Meeting) -> String {
        currentTitleOverride ?? meeting.title
    }

    private func currentNotesText(for meeting: Meeting) -> String {
        currentNotesOverride ?? meeting.userNotesPlainText
    }

    private func titleRenameOverlay(meeting: Meeting) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeTitleRenameDialog()
                }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.current.editTitle)
                        .font(AppTheme.bodyFont(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(AppStrings.current.renameTitlePrompt)
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundStyle(AppTheme.subtleInk)
                }

                TextField(AppStrings.current.untitledNote, text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                    )
                    .focused($isTitleRenameFocused)
                    .onSubmit {
                        commitTitleRename(for: meeting)
                    }
                    .accessibilityIdentifier("TitleRenameField")

                HStack(spacing: 12) {
                    titleDialogButton(
                        title: AppStrings.current.cancel,
                        foreground: AppTheme.subtleInk,
                        border: AppTheme.subtleBorderColor,
                        lineWidth: AppTheme.subtleBorderWidth
                    ) {
                        closeTitleRenameDialog()
                    }
                    .accessibilityIdentifier("TitleRenameCancelButton")

                    titleDialogButton(
                        title: AppStrings.current.save,
                        foreground: AppTheme.ink,
                        border: AppTheme.border,
                        lineWidth: AppTheme.retroBorderWidth
                    ) {
                        commitTitleRename(for: meeting)
                    }
                    .accessibilityIdentifier("TitleRenameSaveButton")
                }
            }
            .padding(20)
            .frame(maxWidth: 360, alignment: .leading)
            .background(AppTheme.surface)
            .softCard()
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("TitleRenameDialog")
        }
    }

    private func titleDialogButton(
        title: String,
        foreground: Color,
        border: Color,
        lineWidth: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(border, lineWidth: lineWidth)
                )
        }
        .buttonStyle(.plain)
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

private struct MeetingNotesDrawer: View {
    let meeting: Meeting
    let initialText: String
    let onClose: () -> Void
    let onTextChange: (String) -> Void

    @State private var draft: String

    init(
        meeting: Meeting,
        initialText: String,
        onClose: @escaping () -> Void,
        onTextChange: @escaping (String) -> Void
    ) {
        self.meeting = meeting
        self.initialText = initialText
        self.onClose = onClose
        self.onTextChange = onTextChange
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppStrings.current.myNotes)
                                .font(AppTheme.bodyFont(size: 22, weight: .bold))
                                .foregroundStyle(AppTheme.ink)

                            Text(AppStrings.current.notesMergeHint)
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("MeetingNotesMergeHint")
                        }

                        Spacer(minLength: 0)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.surface)
                                .overlay(
                                    Rectangle()
                                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("MeetingNotesDrawerCloseButton")
                    }

                    ThinDivider()
                }
                .padding(20)

                ScrollView(showsIndicators: false) {
                    NoteEditorView(
                        text: $draft,
                        showsHeader: false,
                        title: AppStrings.current.notes,
                        placeholder: AppStrings.current.writeHere,
                        minHeight: 320,
                        usesBodyStyle: true,
                        accessibilityIdentifier: "MeetingNotesEditor"
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface)
            .softCard()
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MeetingNotesDrawer")
        .onChange(of: draft) { _, newValue in
            onTextChange(newValue)
        }
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
                .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.highlight)
                .accessibilityIdentifier("EnhancedNotesEditorCancelButton")

                Spacer()

                Button(AppStrings.current.save) {
                    onSave()
                }
                .font(AppTheme.bodyFont(size: 16, weight: .semibold))
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
