import SwiftUI

struct RecordingControlBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        AppGlassCard(cornerRadius: 30, style: .regular, padding: 16, shadowOpacity: 0.14) {
            VStack(spacing: 14) {
                if isActiveMeeting {
                    activeControls
                } else if isOtherMeetingRecording {
                    passiveConflictState
                } else {
                    idleControls
                }
            }
        }
    }

    private var activeControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.highlight)
                    .frame(width: 10, height: 10)

                Text(recordingSessionStore.durationSeconds.mmss)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("RecordDurationLabel")

                Spacer()

                Image(systemName: recordingSessionStore.asrState == .connected ? "waveform" : "waveform.badge.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(recordingSessionStore.asrState == .connected ? AppTheme.accent : AppTheme.highlight)
            }

            WaveformView(samples: recordingSessionStore.waveformSamples)
                .frame(height: 34)
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
                    Image(systemName: recordingSessionStore.phase == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            AppGlassSurface(cornerRadius: 22, style: .clear, shadowOpacity: 0.05)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(recordingSessionStore.phase == .paused ? "继续录音" : "暂停录音")
                        .accessibilityIdentifier("PauseRecordingButton")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("PauseRecordingButton")

                Button {
                    Task {
                        await meetingStore.stopRecording()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("停止录音")
                        .accessibilityIdentifier("StopRecordingButton")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
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
        HStack(spacing: 10) {
            Image(systemName: "mic.badge.xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.highlight)

            Text("另一条会议正在录音")
                .font(.footnote)
                .foregroundStyle(AppTheme.subtleInk)

            Spacer()
        }
    }

    private var idleControls: some View {
        HStack(spacing: 14) {
            ZStack {
                AppGlassSurface(cornerRadius: 22, style: .clear, shadowOpacity: 0.04)
                    .frame(width: 52, height: 52)

                Image(systemName: "doc.text")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.audioLocalPath == nil ? "Ready" : "Resume")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text(meeting.durationLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            Button {
                Task {
                    await meetingStore.startRecording(meetingID: meeting.id)
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink, in: Circle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(meeting.audioLocalPath == nil ? "开始录音" : "继续录音")
                    .accessibilityIdentifier("StartRecordingButton")
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(meeting.audioLocalPath == nil ? "开始录音" : "继续录音")
            .accessibilityIdentifier("StartRecordingButton")
        }
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
