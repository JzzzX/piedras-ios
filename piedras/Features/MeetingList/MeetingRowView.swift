import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isRecording: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                leadingIcon

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(meeting.displayTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        metadataPill(systemName: "clock", label: meeting.durationLabel)
                        metadataPill(systemName: recordingModeIconName, label: "")
                        metadataPill(systemName: "calendar", label: meeting.compactTimestampLabel)

                        if isRecording {
                            metadataPill(systemName: "record.circle.fill", label: "")
                                .foregroundStyle(AppTheme.highlight)
                        } else if meeting.syncState == .failed {
                            metadataPill(systemName: "exclamationmark.circle.fill", label: "")
                                .foregroundStyle(AppTheme.danger)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PaperSurface(
                    cornerRadius: 24,
                    fill: isRecording ? AppTheme.documentPaper : AppTheme.homeCard,
                    border: AppTheme.homeCardBorder,
                    shadowOpacity: isRecording ? 0.10 : 0.08
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("MeetingRow")
    }

    private var leadingIcon: some View {
        ZStack(alignment: .topTrailing) {
            GlassIconBadge(systemName: "doc.text", size: 44, symbolSize: 16, shape: .rounded(18))

            if isRecording {
                Circle()
                    .fill(AppTheme.highlight)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.documentPaper.opacity(0.92), lineWidth: 2)
                    }
                    .offset(x: 3, y: -3)
            }
        }
    }

    private func metadataPill(systemName: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))

            if !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(AppTheme.mutedInk)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            PaperSurface(
                cornerRadius: 12,
                fill: AppTheme.backgroundSecondary.opacity(0.88),
                border: AppTheme.homeCardBorder,
                shadowOpacity: 0.02
            )
        }
    }

    private var recordingModeIconName: String {
        switch meeting.recordingMode {
        case .microphone:
            return "mic.fill"
        case .fileMix:
            return "waveform.and.mic"
        }
    }
}
