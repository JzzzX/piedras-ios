import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    let isDisabled: Bool
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
    @Environment(AnnotationStore.self) private var annotationStore

    let meetingID: String

    @State private var showsTranscriptSheet = false
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
    @State private var recBadgePulse = false
    @State private var recordingNoteFocusRequest = 0
    @State private var isRecordingNoteEditorFocused = false

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
                    VStack(alignment: .leading, spacing: isRecordingThisMeeting ? 12 : 20) {
                        Color.clear
                            .frame(height: 0)
                            .id(topAnchorID)

                        if let transcriptionStatus = meetingStore.fileTranscriptionStatus(meetingID: meeting.id) {
                            fileTranscriptionStatusView(transcriptionStatus, meetingID: meeting.id)
                        }

                        if !isRecordingThisMeeting {
                            titleBlock(meeting: meeting)
                        }

                        documentPage(meeting: meeting)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, contentBottomPadding(for: meeting))
                }
                .onChange(of: isRecordingThisMeeting, initial: false) { wasRecording, isRecording in
                    if wasRecording && !isRecording {
                        // Save any pending notes before transitioning to AI notes view
                        if let meeting = meetingStore.meeting(withID: meetingID) {
                            noteSaveTask?.cancel()
                            let notes = currentNotesText(for: meeting)
                            meetingStore.updateNotes(notes, for: meeting)
                        }

                        withAnimation(.easeOut(duration: 0.4)) {
                            proxy.scrollTo(topAnchorID, anchor: .top)
                        }
                    }

                    if !wasRecording && isRecording {
                        withAnimation(.easeOut(duration: 0.4)) {
                            proxy.scrollTo(topAnchorID, anchor: .top)
                        }
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
        .animation(.easeOut(duration: 0.4), value: isRecordingThisMeeting)
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .safeAreaInset(edge: .top, spacing: 0) {
            detailTopChrome(meeting: meeting)
        }
        .safeAreaInset(edge: .bottom) {
            if isRecordingThisMeeting {
                RecordingBottomBar(
                    meeting: meeting,
                    onRequestTranscript: {
                        annotationStore.dismissEditor()
                        showsTranscriptSheet = true
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                bottomStack(for: meeting)
            }
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
        .sheet(isPresented: $showsTranscriptSheet) {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                MeetingTranscriptSheet(
                    meeting: meeting,
                    isActiveRecording: isRecordingThisMeeting
                ) {
                    annotationStore.dismissEditor()
                    showsTranscriptSheet = false
                }
            }
        }
    }

    private func detailTopChrome(meeting: Meeting) -> some View {
        VStack(spacing: 0) {
            topBar(meeting: meeting)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)

            LinearGradient(
                colors: [AppTheme.background, AppTheme.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
        }
        .background(AppTheme.background)
    }

    private func topBar(meeting: Meeting) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: AppStrings.current.back) {
                closeActionMenu()
                dismiss()
            }
            .accessibilityIdentifier("BackButton")

            Spacer()

            if isRecordingThisMeeting {
                recBadge
            }

            Spacer()

            HStack(spacing: 10) {
                ForEach(MeetingDetailChrome.topBarActions(isRecording: isRecordingThisMeeting), id: \.self) { action in
                    topBarActionButton(action, meeting: meeting)
                }
            }
        }
    }

    private var recBadge: some View {
        Text("● REC")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(AppTheme.surface)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppTheme.highlight)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.ink, lineWidth: AppTheme.retroBorderWidth)
            )
            .opacity(recBadgePulse ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    recBadgePulse.toggle()
                }
            }
            .accessibilityLabel(AppStrings.current.statusRecording)
            .accessibilityIdentifier("RecBadge")
    }

    @ViewBuilder
    private func topBarActionButton(_ action: MeetingDetailToolbarAction, meeting: Meeting) -> some View {
        switch action {
        case .transcript:
            Button {
                closeActionMenu()
                showsTranscriptSheet = true
            } label: {
                detailToolLabel(systemName: "doc.text")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.current.transcript)
            .accessibilityIdentifier("MeetingTranscriptSheetButton")

        case .share:
            ShareLink(item: sharePayload(for: meeting)) {
                detailToolLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.current.share)
            .accessibilityIdentifier("MeetingShareButton")

        case .more:
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

    private func titleBlock(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                openTitleRenameDialog(for: meeting)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(displayTitle(for: meeting))
                        .font(AppTheme.bodyFont(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("MeetingDetailTitleText")

                    Spacer(minLength: 0)

                    titleEditLabel(systemName: "pencil")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityIdentifier("MeetingDetailTitleButton")

            VStack(alignment: .leading, spacing: 8) {
                Text(metaLine(for: meeting))
                    .font(AppTheme.dataFont(size: 14))
                    .foregroundStyle(AppTheme.subtleInk)

                if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                    let transcriptionBadgeLabel = recordingSessionStore.backgroundTranscriptionStatus.badgeLabel
                        ?? (recordingSessionStore.asrState == .connected
                            ? AppStrings.current.liveTranscription
                            : AppStrings.current.reconnecting)
                    let transcriptionBadgeTint = recordingSessionStore.backgroundTranscriptionStatus.badgeLabel == nil
                        ? (recordingSessionStore.asrState == .connected ? AppTheme.success : AppTheme.highlight)
                        : recordingSessionStore.backgroundTranscriptionStatus.tint

                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(transcriptionBadgeTint)
                            .frame(width: 6, height: 6)

                        Text(transcriptionBadgeLabel)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(transcriptionBadgeTint)
                    }
                }
            }

            meetingTypeSelector(meeting: meeting)
        }
    }

    private func actionMenuOverlay(meeting: Meeting) -> some View {
        let chrome = MeetingDetailChrome.actionMenuChrome

        return ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color.black.opacity(chrome.backdropOpacity))
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
            if isRecordingThisMeeting {
                recordingDocumentPage(meeting: meeting)
            } else {
                ThinDivider()

                EnhancedNotesView(
                    text: meeting.enhancedNotes,
                    meetingID: meeting.id
                )
                .padding(.top, 20)
            }
        }
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, minHeight: minimumPageHeight, alignment: .topLeading)
    }

    private func recordingDocumentPage(meeting: Meeting) -> some View {
        let chrome = MeetingDetailChrome.recordingDocument

        return VStack(alignment: .leading, spacing: 0) {
            recordingTitleBlock(meeting: meeting, chrome: chrome)
                .padding(.bottom, 20)

            ThinDivider()
                .padding(.bottom, 20)

            ZStack(alignment: .topLeading) {
                NoteEditorView(
                    text: noteEditorBinding(for: meeting),
                    showsHeader: false,
                    title: AppStrings.current.notes,
                    placeholder: MeetingDetailChrome.recordingNoteEditorPlaceholder(
                        notes: currentNotesText(for: meeting),
                        isEditorFocused: isRecordingNoteEditorFocused
                    ),
                    minHeight: 400,
                    usesBodyStyle: true,
                    focusRequestToken: recordingNoteFocusRequest,
                    isFocused: $isRecordingNoteEditorFocused,
                    accessibilityIdentifier: "RecordingNoteEditor"
                )

                if MeetingDetailChrome.showsRecordingNotePrompt(
                    notes: currentNotesText(for: meeting),
                    isEditorFocused: isRecordingNoteEditorFocused
                ) {
                    recordingNotePrompt(chrome: chrome)
                }
            }

            HStack {
                Spacer()
                Text("· · ·")
                    .font(AppTheme.dataFont(size: 12))
                    .foregroundStyle(AppTheme.subtleInk.opacity(0.4))
                    .tracking(4)
                Spacer()
            }
            .padding(.top, 40)
        }
    }

    private func recordingTitleBlock(
        meeting: Meeting,
        chrome: MeetingDetailRecordingDocumentChrome
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    openTitleRenameDialog(for: meeting)
                } label: {
                    Text(displayTitle(for: meeting))
                        .font(AppTheme.bodyFont(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("MeetingDetailTitleText")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("RecordingDetailTitleButton")

                Button {
                    openTitleRenameDialog(for: meeting)
                } label: {
                    titleEditLabel(systemName: chrome.titleEditSystemName)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.current.editTitle)
                .accessibilityIdentifier("RecordingDetailTitleEditButton")
            }

            Text(MeetingDetailChrome.recordingMetaLine(for: meeting.date))
                .font(AppTheme.dataFont(size: 14))
                .foregroundStyle(AppTheme.subtleInk)
                .accessibilityIdentifier("RecordingDetailMetaText")

            meetingTypeSelector(meeting: meeting)
        }
    }

    private func recordingNotePrompt(chrome: MeetingDetailRecordingDocumentChrome) -> some View {
        Button {
            isRecordingNoteEditorFocused = true
            recordingNoteFocusRequest += 1
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: chrome.notePromptSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.backgroundSecondary)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(chrome.notePromptTitle)
                        .font(AppTheme.bodyFont(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text(chrome.notePromptHint)
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: chrome.notePromptMinHeight, alignment: .topLeading)
            .background(AppTheme.surface.opacity(0.76))
            .overlay(
                Rectangle()
                    .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("RecordingDetailNotePrompt")
    }


    private func noteEditorBinding(for meeting: Meeting) -> Binding<String> {
        Binding(
            get: { currentNotesText(for: meeting) },
            set: { newValue in
                scheduleNoteSave(newValue, for: meeting)
            }
        )
    }

    @ViewBuilder
    private func bottomStack(for meeting: Meeting) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    AppTheme.background.opacity(0),
                    AppTheme.background.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                notesTeaser()
                    .padding(.horizontal, 20)

                detailCTAButton(
                    kind: .chat,
                    accessibilityIdentifier: "MeetingAskButton",
                    glyphIdentifier: "MeetingAskButtonGlyph"
                ) {
                    activeSheet = .chat
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(AppTheme.background)
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
                MeetingChatSheet(onClose: {
                    activeSheet = nil
                }) {
                    ChatView(meeting: meeting)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .presentationBackground(AppTheme.surface)
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
        let chrome = MeetingDetailChrome.actionMenuChrome

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
                .disabled(item.isDisabled)
                .opacity(item.isDisabled ? 0.46 : 1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier(item.accessibilityIdentifier)

                if index < items.count - 1 {
                    ThinDivider()
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: 208, alignment: .leading)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
        .background {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(AppTheme.backgroundSecondary.opacity(chrome.haloOpacity))
                    .padding(-chrome.haloExpansion)

                Rectangle()
                    .fill(AppTheme.mutedInk.opacity(chrome.shadowOpacity))
                    .offset(x: chrome.shadowOffset, y: chrome.shadowOffset)
            }
        }
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }

    private func actionItems(meeting: Meeting) -> [MeetingActionItem] {
        let transcript = meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let menuItems = MeetingDetailChrome.actionMenuItems(
            isRecording: isRecordingThisMeeting,
            hasTranscript: !transcript.isEmpty,
            canRetryTranscription: meetingStore.fileTranscriptionStatus(meetingID: meeting.id)?.canRetry == true
        )

        return menuItems.map { item in
            switch item.accessibilityIdentifier {
            case "MeetingDetailActionEditAINotes":
                return MeetingActionItem(
                    title: item.title,
                    systemName: item.systemName,
                    accessibilityIdentifier: item.accessibilityIdentifier,
                    isDisabled: false
                ) {
                    closeActionMenu()
                    openEnhancedNotesEditor(for: meeting)
                }

            case "MeetingDetailActionRegenerateNotes":
                let isDisabled = meetingStore.isEnhancing(meetingID: meeting.id) || !canRefreshSummary(for: meeting)
                return MeetingActionItem(
                    title: item.title,
                    systemName: meetingStore.isEnhancing(meetingID: meeting.id) ? "hourglass" : item.systemName,
                    accessibilityIdentifier: item.accessibilityIdentifier,
                    isDisabled: isDisabled
                ) {
                    closeActionMenu()
                    Task {
                        await meetingStore.generateEnhancedNotes(for: meeting.id)
                    }
                }

            case "MeetingDetailActionCopyNotes":
                return MeetingActionItem(
                    title: item.title,
                    systemName: item.systemName,
                    accessibilityIdentifier: item.accessibilityIdentifier,
                    isDisabled: false
                ) {
                    closeActionMenu()
                    let content = MarkdownDocumentFormatter.plainText(from: meeting.enhancedNotes)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    UIPasteboard.general.string = content
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showToast(AppStrings.current.copiedNotes)
                }

            case "MeetingDetailActionCopyTranscript":
                return MeetingActionItem(
                    title: item.title,
                    systemName: item.systemName,
                    accessibilityIdentifier: item.accessibilityIdentifier,
                    isDisabled: false
                ) {
                    closeActionMenu()
                    UIPasteboard.general.string = transcript
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showToast(AppStrings.current.copiedTranscript)
                }

            case "MeetingDetailActionRetryTranscription":
                return MeetingActionItem(
                    title: item.title,
                    systemName: item.systemName,
                    accessibilityIdentifier: item.accessibilityIdentifier,
                    isDisabled: false
                ) {
                    closeActionMenu()
                    Task {
                        await meetingStore.retryFileTranscription(meetingID: meeting.id)
                    }
                }

            default:
                return MeetingActionItem(
                    title: item.title,
                    systemName: item.systemName,
                    accessibilityIdentifier: item.accessibilityIdentifier,
                    isDisabled: false,
                    action: {}
                )
            }
        }
    }

    private var minimumPageHeight: CGFloat {
        max(560, UIScreen.main.bounds.height * 0.66)
    }

    private var isRecordingThisMeeting: Bool {
        recordingSessionStore.meetingID == meetingID && recordingSessionStore.phase != .idle
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
        let body = MarkdownDocumentFormatter.plainText(from: meeting.enhancedNotes)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if body.isEmpty {
            return meeting.displayTitle
        }

        return "\(meeting.displayTitle)\n\n\(body)"
    }

    private func copyCurrentContent(for meeting: Meeting) {
        let content = MarkdownDocumentFormatter.plainText(from: meeting.enhancedNotes)
        let toast = AppStrings.current.copiedNotes

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
        if isRecordingThisMeeting {
            return 20  // Bottom bar handled by safeAreaInset
        }

        return 160  // notesTeaser + chatCTA
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
            }

            if status.canRetry {
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
            .foregroundStyle(AppTheme.mutedInk)
            .frame(width: 40, height: 40)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
            )
    }

    private func titleEditLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.subtleInk)
            .frame(width: 28, height: 28)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
            )
    }

    private func notesTeaser() -> some View {
        detailCTAButton(
            kind: .notes,
            accessibilityIdentifier: "MeetingTranscriptNotesTeaser",
            glyphIdentifier: "MeetingTranscriptNotesTeaserGlyph"
        ) {
            closeActionMenu()
            showsNotesDrawer = true
        }
    }

    private func meetingTypeSelector(meeting: Meeting) -> some View {
        let selectedType = MeetingTypeOption(rawValue: meeting.meetingType) ?? .general

        return Menu {
            ForEach(MeetingTypeOption.allCases) { type in
                Button {
                    meetingStore.updateMeetingType(type.rawValue, for: meeting)
                } label: {
                    if type == selectedType {
                        Label(AppStrings.current.meetingTypeName(type), systemImage: "checkmark")
                    } else {
                        Text(AppStrings.current.meetingTypeName(type))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.current.meetingTypeLabel)
                        .font(AppTheme.dataFont(size: 11))
                        .foregroundStyle(AppTheme.subtleInk)

                    Text(AppStrings.current.meetingTypeName(selectedType))
                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(AppStrings.current.meetingTypeHint)
                        .font(AppTheme.dataFont(size: 11))
                        .foregroundStyle(AppTheme.subtleInk)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.subtleInk)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.current.meetingTypeLabel)
        .accessibilityValue(AppStrings.current.meetingTypeName(selectedType))
        .accessibilityIdentifier("MeetingTypeMenu")
    }

    private func detailCTAButton(
        kind: MeetingDetailChromeKind,
        accessibilityIdentifier: String,
        glyphIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        let config = MeetingDetailChrome.entry(for: kind)
        let usesHeroChrome = kind == .chat
        let foreground = usesHeroChrome ? AppTheme.surface : AppTheme.ink
        let background = usesHeroChrome ? AppTheme.ink : AppTheme.surface
        let borderColor = usesHeroChrome ? AppTheme.ink : AppTheme.border
        let lineWidth = usesHeroChrome ? CGFloat(2) : AppTheme.retroBorderWidth

        return Button(action: action) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                detailGlyph(
                    glyph: config.glyph,
                    usesSymbolImage: config.usesSymbolImage,
                    textSize: 13,
                    symbolSize: 14,
                    foreground: foreground,
                    identifier: glyphIdentifier
                )

                Text(config.title)
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundStyle(foreground)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(background)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: lineWidth)
            )
            .retroHardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func detailGlyph(
        glyph: String,
        usesSymbolImage: Bool,
        textSize: CGFloat,
        symbolSize: CGFloat,
        foreground: Color,
        identifier: String
    ) -> some View {
        if usesSymbolImage {
            Image(systemName: glyph)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(foreground)
                .accessibilityIdentifier(identifier)
        } else {
            Text(glyph)
                .font(.system(size: textSize, weight: .bold, design: .monospaced))
                .foregroundStyle(foreground)
                .accessibilityIdentifier(identifier)
        }
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

private struct MeetingDetailSurfaceSheet<Content: View>: View {
    let chrome: MeetingDetailSheetChrome
    let accessibilityIdentifier: String
    let glyphIdentifier: String
    let titleIdentifier: String
    let closeIdentifier: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if chrome.usesSymbolImage {
                        Image(systemName: chrome.glyph)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .accessibilityIdentifier(glyphIdentifier)
                    } else {
                        Text(chrome.glyph)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)
                            .accessibilityIdentifier(glyphIdentifier)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chrome.title)
                            .font(AppTheme.bodyFont(size: 24, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .accessibilityIdentifier(titleIdentifier)

                        if let hint = chrome.hint {
                            Text(hint)
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                .accessibilityIdentifier(closeIdentifier)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, chrome.hint == nil ? 16 : 14)

            ThinDivider()
                .padding(.horizontal, 20)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppTheme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct MeetingNotesDrawer: View {
    let initialText: String
    let onClose: () -> Void
    let onTextChange: (String) -> Void

    @State private var draft: String

    init(
        initialText: String,
        onClose: @escaping () -> Void,
        onTextChange: @escaping (String) -> Void
    ) {
        self.initialText = initialText
        self.onClose = onClose
        self.onTextChange = onTextChange
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        MeetingDetailSurfaceSheet(
            chrome: MeetingDetailChrome.sheet(for: .notes),
            accessibilityIdentifier: "MeetingNotesDrawer",
            glyphIdentifier: "MeetingNotesDrawerGlyph",
            titleIdentifier: "MeetingNotesDrawerTitle",
            closeIdentifier: "MeetingNotesDrawerCloseButton",
            onClose: onClose
        ) {
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
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.surface)
        .onChange(of: draft) { _, newValue in
            onTextChange(newValue)
        }
    }
}

private struct MeetingChatSheet<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        MeetingDetailSurfaceSheet(
            chrome: MeetingDetailChrome.sheet(for: .chat),
            accessibilityIdentifier: "MeetingChatSheet",
            glyphIdentifier: "MeetingChatSheetGlyph",
            titleIdentifier: "MeetingChatSheetTitle",
            closeIdentifier: "MeetingChatSheetCloseButton",
            onClose: onClose
        ) {
            content()
        }
    }
}

private struct MeetingTranscriptSheet: View {
    @Environment(AnnotationStore.self) private var annotationStore

    let meeting: Meeting
    let isActiveRecording: Bool
    let onClose: () -> Void

    private var audioSectionMode: TranscriptAudioSectionMode {
        TranscriptAudioSectionPresentation.mode(
            for: meeting,
            isActiveRecording: isActiveRecording
        )
    }

    var body: some View {
        MeetingDetailSurfaceSheet(
            chrome: MeetingDetailSheetChrome(
                title: AppStrings.current.transcript,
                glyph: "doc.text",
                usesSymbolImage: true,
                hint: nil
            ),
            accessibilityIdentifier: "MeetingTranscriptSheet",
            glyphIdentifier: "MeetingTranscriptSheetGlyph",
            titleIdentifier: "MeetingTranscriptSheetTitle",
            closeIdentifier: "MeetingTranscriptSheetCloseButton",
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    TranscriptView(meeting: meeting)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)

                if audioSectionMode != .hidden {
                    ThinDivider()
                    transcriptAudioSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.surface)
        .onDisappear {
            annotationStore.dismissEditor()
        }
    }

    @ViewBuilder
    private var transcriptAudioSection: some View {
        switch audioSectionMode {
        case .hidden:
            EmptyView()
        case .recordingNotice:
            TranscriptRecordingNoticeBar()
        case let .player(sourceURL):
            AudioPlaybackBar(sourceURL: sourceURL)
        }
    }
}

private struct TranscriptRecordingNoticeBar: View {
    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(label: AppStrings.current.playback)

            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.highlight)

                Text(AppStrings.current.transcriptRecordingNotice)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
        .accessibilityIdentifier("TranscriptRecordingNotice")
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
