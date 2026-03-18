import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isRecording: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingIcon

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(meeting.displayTitle)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    syncBadge
                }

                HStack(spacing: 8) {
                    metadataPill(systemName: "clock", label: meeting.durationLabel)
                    metadataPill(systemName: "waveform", label: meeting.transcriptCountLabel)
                    metadataPill(systemName: "calendar", label: meeting.compactTimestampLabel)

                    if isRecording {
                        metadataPill(systemName: "record.circle.fill", label: "")
                            .foregroundStyle(AppTheme.highlight)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AppGlassSurface(
                cornerRadius: 24,
                style: isRecording ? .regular : .clear,
                borderOpacity: isRecording ? 0.30 : 0.22,
                shadowOpacity: 0.08
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("MeetingRow")
        .onTapGesture(perform: onOpen)
    }

    private var leadingIcon: some View {
        ZStack(alignment: .topTrailing) {
            AppGlassSurface(cornerRadius: 18, style: .regular, shadowOpacity: 0.04)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }

            if isRecording {
                Circle()
                    .fill(AppTheme.highlight)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
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
            AppGlassSurface(cornerRadius: 12, style: .clear, shadowOpacity: 0.02)
        }
    }

    private var syncBadge: some View {
        Image(systemName: meeting.syncStateIconName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(syncForeground)
            .frame(width: 24, height: 24)
            .background {
                AppGlassSurface(cornerRadius: 12, style: .clear, shadowOpacity: 0.02)
            }
            .accessibilityLabel(meeting.syncStateLabel)
    }

    private var syncForeground: Color {
        switch meeting.syncState {
        case .pending:
            return AppTheme.highlight
        case .syncing:
            return AppTheme.accent
        case .synced:
            return AppTheme.success
        case .failed:
            return AppTheme.danger
        case .deleted:
            return AppTheme.subtleInk
        }
    }
}
