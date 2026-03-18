import SwiftUI
import UniformTypeIdentifiers

private enum MeetingDetailMode: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case summary = "AI Notes"

    var id: String { rawValue }
}

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meetingID: String

    @State private var selectedMode: MeetingDetailMode = .transcript
    @State private var noteSaveTask: Task<Void, Never>?
    @State private var showsRecordingModeDialog = false
    @State private var isImportingSourceAudio = false
    @State private var showsRawNotesSheet = false
    @State private var showsMeetingChatSheet = false

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
        }
    }

    private func detailScene(meeting: Meeting) -> some View {
        ZStack {
            DocumentBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    topBar
                    titleBlock(meeting: meeting)
                    modePicker
                    contentPanel(meeting: meeting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, contentBottomPadding(for: meeting))
            }
        }
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
        .sheet(isPresented: $showsRawNotesSheet) {
            rawNotesSheet
        }
        .sheet(isPresented: $showsMeetingChatSheet) {
            meetingChatSheet
        }
    }

    private var topBar: some View {
        HStack {
            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: "返回") {
                dismiss()
            }
            .accessibilityIdentifier("BackButton")

            Spacer()

            Menu {
                Button("编辑原始笔记", systemImage: "square.and.pencil") {
                    showsRawNotesSheet = true
                }

                Button("Chat with note", systemImage: "bubble.left.and.sparkles") {
                    showsMeetingChatSheet = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
                    .background {
                        PaperSurface(
                            cornerRadius: 20,
                            fill: AppTheme.documentPaperSecondary,
                            border: AppTheme.documentHairline,
                            shadowOpacity: 0.04
                        )
                    }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            Text("Piedras AI")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func titleBlock(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Untitled note",
                text: Binding(
                    get: { meeting.title },
                    set: { meetingStore.updateTitle($0, for: meeting) }
                )
            )
            .font(.system(size: 38, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .textFieldStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(metaLine(for: meeting))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)

                if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                    Text(recordingSessionStore.asrState == .connected ? "Live transcription connected" : "Live transcription reconnecting")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(recordingSessionStore.asrState == .connected ? AppTheme.documentOlive : AppTheme.highlight)
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $selectedMode) {
            ForEach(MeetingDetailMode.allCases) { mode in
                Text(mode.rawValue)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private func contentPanel(meeting: Meeting) -> some View {
        PaperCard(
            cornerRadius: 34,
            fill: AppTheme.documentPaper,
            border: AppTheme.documentHairline,
            padding: 22,
            shadowOpacity: 0.06
        ) {
            Group {
                if selectedMode == .transcript {
                    TranscriptView(meeting: meeting)
                } else {
                    EnhancedNotesView(meeting: meeting)
                }
            }
        }
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
                showsMeetingChatSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Chat with note")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.46, green: 0.62, blue: 0.92),
                            Color(red: 0.55, green: 0.71, blue: 0.96),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var rawNotesSheet: some View {
        NavigationStack {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                ZStack {
                    DocumentBackdrop()

                    ScrollView(showsIndicators: false) {
                        NoteEditorView(meeting: meeting, showsHeader: false) { newValue in
                            scheduleNoteSave(newValue, for: meeting)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
                .navigationTitle("Raw Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showsRawNotesSheet = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var meetingChatSheet: some View {
        NavigationStack {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                ChatView(meeting: meeting)
                    .navigationTitle("Chat with note")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showsMeetingChatSheet = false
                            }
                        }
                    }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func scheduleNoteSave(_ newValue: String, for meeting: Meeting) {
        noteSaveTask?.cancel()
        noteSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            meetingStore.updateNotes(newValue, for: meeting)
        }
    }

    private func metaLine(for meeting: Meeting) -> String {
        let date = meeting.date.formatted(.dateTime.month(.wide).day().year())
        let duration = meeting.durationSeconds > 0 ? "\(meeting.durationLabel) recording" : "Not recorded yet"
        return "\(date) · \(duration)"
    }

    private func contentBottomPadding(for meeting: Meeting) -> CGFloat {
        if recordingSessionStore.phase != .idle {
            return 190
        }

        switch selectedMode {
        case .transcript:
            return meeting.audioLocalPath == nil ? 56 : 170
        case .summary:
            return 140
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
}
