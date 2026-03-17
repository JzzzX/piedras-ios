import SwiftUI

struct RecordingControlBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        VStack(spacing: 14) {
            if isActiveMeeting {
                activeControls
            } else if isOtherMeetingRecording {
                passiveConflictState
            } else {
                idleControls
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.border.opacity(0.65), lineWidth: 1)
        }
    }

    private var activeControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                statusPill(
                    title: recordingSessionStore.phase.displayLabel,
                    systemImage: "record.circle.fill",
                    tint: AppTheme.highlightSoft,
                    foreground: AppTheme.highlight
                )
                statusPill(
                    title: recordingSessionStore.asrState.displayLabel,
                    systemImage: "waveform",
                    tint: AppTheme.accentSoft,
                    foreground: AppTheme.accent
                )
                Spacer()
                Text(recordingSessionStore.durationSeconds.mmss)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("RecordDurationLabel")
            }

            WaveformView(samples: recordingSessionStore.waveformSamples)
                .frame(height: 42)
                .foregroundStyle(AppTheme.accent)

            HStack(spacing: 12) {
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
                        recordingSessionStore.phase == .paused ? "Resume" : "Pause",
                        systemImage: recordingSessionStore.phase == .paused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ink)
                .background(AppTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("PauseRecordingButton")

                Button {
                    Task {
                        await meetingStore.stopRecording()
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("StopRecordingButton")
            }

            if let info = currentBannerMessage {
                Text(info)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.subtleInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var passiveConflictState: some View {
        Label("另一条会议正在录音，先结束当前会话再切换。", systemImage: "mic.badge.xmark")
            .font(.footnote)
            .foregroundStyle(AppTheme.subtleInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private var idleControls: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.audioLocalPath == nil ? "Ready to record" : "Resume capture")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text("Open the mic, stream live transcript, and let the note build itself.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            Button {
                Task {
                    await meetingStore.startRecording(meetingID: meeting.id)
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(meeting.audioLocalPath == nil ? "开始录音" : "继续录音")
            .accessibilityIdentifier("StartRecordingButton")
        }
    }

    private func statusPill(title: String, systemImage: String, tint: Color, foreground: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }

    private var currentBannerMessage: String? {
        if let error = recordingSessionStore.errorBanner, !error.isEmpty {
            return error
        }

        if let info = recordingSessionStore.infoBanner, !info.isEmpty {
            return info
        }

        return nil
    }

    private var isActiveMeeting: Bool {
        recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle
    }

    private var isOtherMeetingRecording: Bool {
        guard let recordingMeetingID = recordingSessionStore.meetingID else { return false }
        return recordingMeetingID != meeting.id && recordingSessionStore.phase != .idle
    }
}
