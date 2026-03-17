import SwiftUI

private enum MeetingDetailMode: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case summary = "AI"

    var id: String { rawValue }

    var systemName: String {
        switch self {
        case .transcript:
            return "text.alignleft"
        case .summary:
            return "sparkles"
        }
    }
}

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meetingID: String

    @State private var selectedMode: MeetingDetailMode = .transcript
    @State private var noteSaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                ZStack {
                    AppGlassBackdrop()

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            titleBlock(meeting: meeting)
                            workspace(meeting: meeting)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 156)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom) {
                    RecordingControlBar(meeting: meeting)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(Color.clear)
                }
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

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: "返回") {
                dismiss()
            }
            .accessibilityIdentifier("BackButton")

            Spacer()

            modeSwitcher
        }
    }

    private func titleBlock(meeting: Meeting) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                AppGlassSurface(cornerRadius: 24, style: .regular, shadowOpacity: 0.05)
                    .frame(width: 60, height: 60)

                Image(systemName: "doc.text")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "Untitled note",
                    text: Binding(
                        get: { meeting.title },
                        set: { meetingStore.updateTitle($0, for: meeting) }
                    )
                )
                .font(.system(size: 38, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .textFieldStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        metadataPill(systemName: "calendar", label: meeting.detailTimestampLabel)
                        metadataPill(systemName: "clock", label: meeting.durationLabel)
                        metadataPill(systemName: meeting.statusIconName, label: meeting.statusLabel)

                        if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                            metadataPill(systemName: "waveform", label: recordingSessionStore.asrState.displayLabel)
                        }
                    }
                }
            }
        }
    }

    private func workspace(meeting: Meeting) -> some View {
        AppGlassCard(cornerRadius: 38, style: .regular, padding: 22, shadowOpacity: 0.10) {
            Group {
                if selectedMode == .transcript {
                    TranscriptView(meeting: meeting)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        NoteEditorView(meeting: meeting) { newValue in
                            noteSaveTask?.cancel()
                            noteSaveTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.5))
                                guard !Task.isCancelled else { return }
                                meetingStore.updateNotes(newValue, for: meeting)
                            }
                        }

                        AppGlassDivider()

                        EnhancedNotesView(meeting: meeting)
                    }
                }
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(MeetingDetailMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selectedMode == mode ? Color.white : AppTheme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background {
                        if selectedMode == mode {
                            Capsule().fill(AppTheme.ink)
                        } else {
                            Capsule().fill(Color.clear)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            AppGlassSurface(cornerRadius: 24, style: .regular, shadowOpacity: 0.06)
                .clipShape(Capsule())
        }
    }

    private func metadataPill(systemName: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.mutedInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            AppGlassSurface(cornerRadius: 16, style: .clear, shadowOpacity: 0.03)
        }
    }
}
