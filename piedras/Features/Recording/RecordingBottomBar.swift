import SwiftUI

/// Bottom-anchored recording control bar with transcript preview and playback controls.
/// Replaces the old `CollapsibleRecordingBar` in the "Immersive Desk" recording experience.
struct RecordingBottomBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting
    var isEditorFocused = false
    var onRequestTranscript: (() -> Void)? = nil
    var onDismissKeyboard: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if !isEditorFocused {
                // Row 1: Transcript preview
                transcriptPreviewRow
            }

            // Row 2: Controls
            controlRow
        }
        .background(AppTheme.dockSurface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Transcript Preview Row

    private var transcriptPreviewRow: some View {
        Button {
            onRequestTranscript?()
        } label: {
            HStack(spacing: 8) {
                Text("≡")
                    .font(AppTheme.dataFont(size: 12))
                    .foregroundStyle(AppTheme.mutedInk)

                Text(transcriptPreviewText)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.mutedInk)
                    .italic()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("▸")
                    .font(AppTheme.dataFont(size: 11))
                    .foregroundStyle(AppTheme.mutedInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border.opacity(0.3))
                .frame(height: AppTheme.retroBorderWidth)
        }
        .accessibilityLabel(AppStrings.current.transcript)
        .accessibilityIdentifier("RecordingBottomBarTranscriptTrigger")
    }

    // MARK: - Control Row

    private var controlRow: some View {
        HStack(spacing: 12) {
            // Pause / Resume button
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
            }
            .buttonStyle(.plain)
            .disabled(recordingSessionStore.phase == .stopping)
            .accessibilityLabel(recordingSessionStore.phase == .paused ? AppStrings.current.resumeRecording : AppStrings.current.pauseRecording)
            .accessibilityIdentifier("RecordingBottomBarPauseButton")

            Spacer()

            // Duration + waveform / paused label
            HStack(spacing: 10) {
                Text(recordingSessionStore.durationSeconds.mmss)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(isPaused ? AppTheme.mutedInk : AppTheme.ink)

                if isPaused {
                    Text(AppStrings.current.statusPaused)
                        .font(AppTheme.dataFont(size: 11))
                        .foregroundStyle(AppTheme.subtleInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border.opacity(0.4), lineWidth: AppTheme.retroBorderWidth)
                        )
                } else {
                    WaveformView(samples: recordingSessionStore.waveformSamples)
                        .frame(width: 48, height: 16)
                }
            }

            Spacer()

            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var isPaused: Bool {
        recordingSessionStore.phase == .paused
    }

    private var actionButton: some View {
        Group {
            if isEditorFocused {
                Button {
                    onDismissKeyboard?()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 84, height: 44)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.current.dismissKeyboard)
                .accessibilityIdentifier("RecordingBottomBarDismissKeyboardButton")
            } else {
                Button {
                    Task {
                        await meetingStore.stopRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(AppStrings.current.stop)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(AppTheme.surface)
                    .frame(width: 84, height: 44)
                    .background(AppTheme.highlight)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(recordingSessionStore.phase == .stopping)
                .accessibilityLabel(AppStrings.current.stopRecording)
                .accessibilityIdentifier("StopRecordingButton")
            }
        }
    }

    private var transcriptPreviewText: String {
        if isPaused {
            return AppStrings.current.transcriptPausedHint
        }

        let partial = recordingSessionStore.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            return partial
        }

        if let lastSegment = meeting.orderedSegments.last?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastSegment.isEmpty {
            return lastSegment
        }

        return AppStrings.current.liveTranscriptTapHint
    }
}
