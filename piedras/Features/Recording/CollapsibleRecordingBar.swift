import SwiftUI

struct CollapsibleRecordingBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Collapsed State

    private var collapsedContent: some View {
        HStack(spacing: 10) {
            // Recording indicator + duration
            HStack(spacing: 6) {
                Rectangle()
                    .fill(AppTheme.highlight)
                    .frame(width: 8, height: 8)

                Text(recordingSessionStore.durationSeconds.mmss)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("CollapsibleRecordDuration")
            }

            // Compact waveform
            WaveformView(samples: recordingSessionStore.waveformSamples)
                .frame(height: 16)

            // Status text
            Text(statusLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.subtleInk)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    // MARK: - Expanded State

    private var expandedContent: some View {
        VStack(spacing: 12) {
            // Top row: indicator + duration + status
            HStack(spacing: 6) {
                Rectangle()
                    .fill(AppTheme.highlight)
                    .frame(width: 10, height: 10)

                Text(recordingSessionStore.durationSeconds.mmss)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            // Latest transcript preview
            let preview = latestTranscriptPreview
            if !preview.isEmpty {
                Text(preview)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Control buttons
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                }
                .buttonStyle(.plain)
                .disabled(recordingSessionStore.phase == .stopping)
                .accessibilityLabel(recordingSessionStore.phase == .paused ? AppStrings.current.resumeRecording : AppStrings.current.pauseRecording)
                .accessibilityIdentifier("CollapsiblePauseButton")

                Button {
                    Task {
                        await meetingStore.stopRecording()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AppTheme.highlight)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(recordingSessionStore.phase == .stopping)
                .accessibilityLabel(AppStrings.current.stopRecording)
                .accessibilityIdentifier("CollapsibleStopButton")
            }
        }
        .padding(14)
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch recordingSessionStore.phase {
        case .recording:
            return AppStrings.current.statusRecording
        case .paused:
            return AppStrings.current.statusPaused
        case .stopping:
            return AppStrings.current.phaseStopping
        default:
            return AppStrings.current.recordingTitle
        }
    }

    private var latestTranscriptPreview: String {
        let partial = recordingSessionStore.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            return partial
        }
        return meeting.orderedSegments.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
