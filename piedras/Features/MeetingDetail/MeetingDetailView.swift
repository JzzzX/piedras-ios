import SwiftUI

private enum MeetingDetailTab: String, CaseIterable, Identifiable {
    case notes = "笔记"
    case transcript = "转写"
    case ai = "AI"

    var id: String { rawValue }
}

struct MeetingDetailView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meetingID: String

    @State private var selectedTab: MeetingDetailTab = .notes
    @State private var noteSaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let meeting = meetingStore.meeting(withID: meetingID) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField(
                            "无标题会议",
                            text: Binding(
                                get: { meeting.title },
                                set: { meetingStore.updateTitle($0, for: meeting) }
                            )
                        )
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Label(meeting.statusLabel, systemImage: meeting.statusIconName)
                            Label(meeting.durationLabel, systemImage: "clock")
                            Label(meeting.syncStateLabel, systemImage: "arrow.triangle.2.circlepath")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if recordingSessionStore.meetingID == meeting.id {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("当前录音会话")
                                    .font(.subheadline.weight(.semibold))
                                Text("阶段：\(recordingSessionStore.phase.rawValue) · ASR：\(recordingSessionStore.asrState.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.thinMaterial)

                    Picker("内容", selection: $selectedTab) {
                        ForEach(MeetingDetailTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    Group {
                        switch selectedTab {
                        case .notes:
                            NoteEditorView(meeting: meeting) { newValue in
                                noteSaveTask?.cancel()
                                noteSaveTask = Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.5))
                                    guard !Task.isCancelled else { return }
                                    meetingStore.updateNotes(newValue, for: meeting)
                                }
                            }
                        case .transcript:
                            TranscriptView(meeting: meeting)
                        case .ai:
                            ScrollView {
                                VStack(spacing: 16) {
                                    EnhancedNotesView(meeting: meeting)
                                    ChatView(meeting: meeting)
                                }
                                .padding()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    RecordingControlBar(meeting: meeting)
                }
                .navigationTitle(meeting.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
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
}
