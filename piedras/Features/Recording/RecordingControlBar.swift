import SwiftUI

struct RecordingControlBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        VStack(spacing: 14) {
            if isActiveMeeting {
                WaveformView(samples: recordingSessionStore.waveformSamples)
                    .frame(height: 44)

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        Task {
                            await meetingStore.stopRecording()
                        }
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            switch recordingSessionStore.phase {
                            case .paused:
                                await meetingStore.resumeRecording()
                            default:
                                await meetingStore.pauseRecording()
                            }
                        }
                    } label: {
                        Label(
                            recordingSessionStore.phase == .paused ? "继续" : "暂停",
                            systemImage: recordingSessionStore.phase == .paused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("录音时长 \(recordingSessionStore.durationSeconds.mmss)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if isOtherMeetingRecording {
                Label("另一场会议正在录音中，请先结束当前录音。", systemImage: "waveform.and.mic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        await meetingStore.startRecording(meetingID: meeting.id)
                    }
                } label: {
                    Label(meeting.audioLocalPath == nil ? "开始录音" : "继续录音", systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if !isActiveMeeting, let audioLocalPath = meeting.audioLocalPath {
                AudioPlaybackBar(filePath: audioLocalPath)
            }

            if let error = recordingSessionStore.errorBanner, isActiveMeeting {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var isActiveMeeting: Bool {
        recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle
    }

    private var isOtherMeetingRecording: Bool {
        guard let recordingMeetingID = recordingSessionStore.meetingID else { return false }
        return recordingMeetingID != meeting.id && recordingSessionStore.phase != .idle
    }
}
