import SwiftUI

private enum MeetingDetailMode: String, CaseIterable, Identifiable {
    case summary = "Smart Notes"
    case transcript = "Transcript"

    var id: String { rawValue }
}

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meetingID: String

    @State private var selectedMode: MeetingDetailMode = .summary
    @State private var noteSaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                ZStack {
                    AppTheme.pageGradient
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            header(meeting: meeting)
                            titleBlock(meeting: meeting)
                            metadataRow(meeting: meeting)

                            if selectedMode == .summary {
                                NoteEditorView(meeting: meeting) { newValue in
                                    noteSaveTask?.cancel()
                                    noteSaveTask = Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.5))
                                        guard !Task.isCancelled else { return }
                                        meetingStore.updateNotes(newValue, for: meeting)
                                    }
                                }

                                EnhancedNotesView(meeting: meeting)
                            } else {
                                TranscriptView(meeting: meeting)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 212)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        Button {
                            router.showGlobalChat()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.headline)
                                Text("Ask anything")
                                    .font(.headline)
                                Spacer()
                            }
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 18)
                            .frame(height: 54)
                            .background(AppTheme.surface, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)

                        RecordingControlBar(meeting: meeting)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .background(.ultraThinMaterial)
                }
            } else {
                ContentUnavailableView(
                    "会议不存在",
                    systemImage: "exclamationmark.triangle",
                    description: Text("这条会议可能已被删除，或者尚未完成本地加载。")
                )
            }
        }
        .onDisappear {
            noteSaveTask?.cancel()
        }
    }

    private func header(meeting: Meeting) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("BackButton")

            Spacer()

            modeSwitcher
        }
    }

    private func titleBlock(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "Untitled note",
                text: Binding(
                    get: { meeting.title },
                    set: { meetingStore.updateTitle($0, for: meeting) }
                )
            )
            .font(.system(size: 40, weight: .regular, design: .serif))
            .foregroundStyle(AppTheme.ink)
            .textFieldStyle(.plain)

            Text(meeting.detailTimestampLabel)
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtleInk)
        }
    }

    private func metadataRow(meeting: Meeting) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                metadataChip(
                    title: meeting.statusLabel,
                    systemImage: meeting.statusIconName,
                    tint: meeting.status == .recording ? AppTheme.highlightSoft : AppTheme.backgroundSecondary,
                    foreground: meeting.status == .recording ? AppTheme.highlight : AppTheme.mutedInk
                )
                metadataChip(
                    title: meeting.durationLabel,
                    systemImage: "clock",
                    tint: AppTheme.backgroundSecondary,
                    foreground: AppTheme.mutedInk
                )
                metadataChip(
                    title: meeting.syncStateLabel,
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: syncTintBackground(for: meeting),
                    foreground: syncForeground(for: meeting)
                )
                metadataChip(
                    title: meeting.transcriptSummaryLabel,
                    systemImage: "text.quote",
                    tint: AppTheme.accentSoft,
                    foreground: AppTheme.accent
                )

                if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                    metadataChip(
                        title: recordingSessionStore.asrState.displayLabel,
                        systemImage: "waveform",
                        tint: AppTheme.highlightSoft,
                        foreground: AppTheme.highlight
                    )
                }
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(MeetingDetailMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedMode == mode ? .white : AppTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(
                            Group {
                                if selectedMode == mode {
                                    Capsule().fill(AppTheme.ink)
                                } else {
                                    Capsule().fill(Color.clear)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.surface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
        }
    }

    private func metadataChip(title: String, systemImage: String, tint: Color, foreground: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }

    private func syncForeground(for meeting: Meeting) -> Color {
        switch meeting.syncState {
        case .pending:
            return AppTheme.highlight
        case .syncing:
            return AppTheme.accent
        case .synced:
            return AppTheme.success
        case .failed:
            return AppTheme.danger
        case .deleted:
            return AppTheme.subtleInk
        }
    }

    private func syncTintBackground(for meeting: Meeting) -> Color {
        switch meeting.syncState {
        case .pending:
            return AppTheme.highlightSoft
        case .syncing:
            return AppTheme.accentSoft
        case .synced:
            return AppTheme.success.opacity(0.14)
        case .failed:
            return AppTheme.danger.opacity(0.12)
        case .deleted:
            return AppTheme.backgroundSecondary
        }
    }
}
