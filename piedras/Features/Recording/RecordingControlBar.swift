import SwiftUI

struct RecordingControlBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting
    var onRequestStartRecording: (() -> Void)? = nil

    var body: some View {
        PaperCard(
            cornerRadius: 30,
            fill: AppTheme.documentPaper,
            border: AppTheme.documentHairline,
            padding: 16,
            shadowOpacity: 0.12
        ) {
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
                            PaperSurface(
                                cornerRadius: 22,
                                fill: AppTheme.documentPaperSecondary,
                                border: AppTheme.documentHairline,
                                shadowOpacity: 0.04
                            )
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

            if showsSourcePlaybackStrip {
                sourcePlaybackStrip
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
            GlassIconBadge(systemName: "doc.text", size: 52, symbolSize: 19, shape: .rounded(20))

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
                if let onRequestStartRecording {
                    onRequestStartRecording()
                } else {
                    Task {
                        await meetingStore.startRecording(meetingID: meeting.id)
                    }
                }
            } label: {
                GlassIconBadge(systemName: "mic.fill", size: 52, symbolSize: 18, shape: .circle)
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

    private var sourcePlaybackStrip: some View {
        HStack(spacing: 10) {
            GlassIconBadge(systemName: "music.note", size: 34, symbolSize: 12, shape: .rounded(14))

            VStack(alignment: .leading, spacing: 3) {
                Text(recordingSessionStore.sourceAudioDisplayName ?? "Source")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Text(sourceProgressLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            Button {
                meetingStore.toggleSourceAudioPlayback()
            } label: {
                GlassIconBadge(
                    systemName: recordingSessionStore.isSourceAudioPlaying ? "pause.fill" : "play.fill",
                    size: 34,
                    symbolSize: 12,
                    shape: .rounded(14)
                )
            }
            .buttonStyle(.plain)
            .disabled(recordingSessionStore.phase != .recording)
        }
    }

    private var sourceProgressLabel: String {
        let current = recordingSessionStore.sourceAudioCurrentTime.mmss
        let duration = recordingSessionStore.sourceAudioDuration.mmss
        return "\(current) / \(duration)"
    }

    private var showsSourcePlaybackStrip: Bool {
        recordingSessionStore.inputMode == .fileMix
            && recordingSessionStore.meetingID == meeting.id
            && recordingSessionStore.sourceAudioDisplayName != nil
    }

    private var isActiveMeeting: Bool {
        recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle
    }

    private var isOtherMeetingRecording: Bool {
        guard let recordingMeetingID = recordingSessionStore.meetingID else { return false }
        return recordingMeetingID != meeting.id && recordingSessionStore.phase != .idle
    }
}
