import SwiftUI

struct RecordingControlBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore
    @Environment(SettingsStore.self) private var settingsStore

    let meeting: Meeting
    var onRequestStartRecording: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(label: isActiveMeeting ? AppStrings.current.recordingTitle : AppStrings.current.recorderTitle)

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
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
        .id(settingsStore.appLanguage)
    }

    private var activeControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(AppTheme.highlight)
                    .frame(width: 10, height: 10)

                Text(recordingSessionStore.durationSeconds.mmss)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("RecordDurationLabel")

                Spacer()

                Text(recordingSessionStore.asrState == .connected ? "ASR:OK" : "ASR:ERR")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(recordingSessionStore.asrState == .connected ? AppTheme.success : AppTheme.highlight)
            }

            WaveformView(samples: recordingSessionStore.waveformSamples)
                .frame(height: 34)

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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                        .retroHardShadow(x: 2, y: 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(recordingSessionStore.phase == .paused ? AppStrings.current.resumeRecording : AppStrings.current.pauseRecording)
                        .accessibilityIdentifier("PauseRecordingButton")
                }
                .buttonStyle(.plain)
                .disabled(recordingSessionStore.phase == .stopping)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("PauseRecordingButton")

                Button {
                    Task {
                        await meetingStore.stopRecording()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.highlight)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                        .retroHardShadow(x: 2, y: 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppStrings.current.stopRecording)
                        .accessibilityIdentifier("StopRecordingButton")
                }
                .buttonStyle(.plain)
                .disabled(recordingSessionStore.phase == .stopping)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("StopRecordingButton")
            }

            if let info = currentBannerMessage {
                Text(info)
                    .font(AppTheme.bodyFont(size: 12))
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.highlight)

            Text(AppStrings.current.anotherMeetingRecording)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.subtleInk)

            Spacer()
        }
    }

    private var idleControls: some View {
        HStack(spacing: 14) {
            RetroIconBadge(systemName: "doc.text", size: 52, symbolSize: 19)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.audioLocalPath == nil ? AppStrings.current.ready : AppStrings.current.resume)
                    .font(AppTheme.bodyFont(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)

                Text(meeting.durationLabel)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
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
                RetroIconBadge(systemName: "mic.fill", size: 52, symbolSize: 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(meeting.audioLocalPath == nil ? AppStrings.current.startRecording : AppStrings.current.resumeRecording)
                    .accessibilityIdentifier("StartRecordingButton")
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(meeting.audioLocalPath == nil ? AppStrings.current.startRecording : AppStrings.current.resumeRecording)
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
            RetroIconBadge(systemName: "music.note", size: 34, symbolSize: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(recordingSessionStore.sourceAudioDisplayName ?? AppStrings.current.source)
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Text(sourceProgressLabel)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            Button {
                meetingStore.toggleSourceAudioPlayback()
            } label: {
                RetroIconBadge(
                    systemName: recordingSessionStore.isSourceAudioPlaying ? "pause.fill" : "play.fill",
                    size: 34,
                    symbolSize: 12
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
