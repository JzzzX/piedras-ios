import SwiftUI

struct RecordingControlBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting
    var onRequestStartRecording: (() -> Void)? = nil

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

            if showsSourcePlaybackStrip {
                sourcePlaybackStrip
            }

            diagnosticsStrip
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
                if let onRequestStartRecording {
                    onRequestStartRecording()
                } else {
                    Task {
                        await meetingStore.startRecording(meetingID: meeting.id)
                    }
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

    private var sourcePlaybackStrip: some View {
        HStack(spacing: 10) {
            ZStack {
                AppGlassSurface(cornerRadius: 16, style: .clear, shadowOpacity: 0.02)
                    .frame(width: 34, height: 34)

                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }

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
                Image(systemName: recordingSessionStore.isSourceAudioPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 34, height: 34)
                    .background {
                        AppGlassSurface(cornerRadius: 17, style: .clear, shadowOpacity: 0.03)
                    }
            }
            .buttonStyle(.plain)
            .disabled(recordingSessionStore.phase != .recording)
        }
    }

    private var diagnosticsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                diagnosticPill(systemName: "mic.fill", label: recordingSessionStore.inputMode.label)
                diagnosticPill(systemName: "waveform", label: "\(recordingSessionStore.capturedPCMChunks)")
                diagnosticPill(systemName: "dot.radiowaves.left.and.right", label: "\(recordingSessionStore.sentPCMChunks)")
            }

            Text("\(recordingSessionStore.audioCaptureState) · \(recordingSessionStore.lastASRTransportMessage)")
                .font(.caption2)
                .foregroundStyle(AppTheme.subtleInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticPill(systemName: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))

            Text(label)
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(AppTheme.mutedInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            AppGlassSurface(cornerRadius: 14, style: .clear, shadowOpacity: 0.02)
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
