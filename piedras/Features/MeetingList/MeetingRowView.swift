import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isRecording: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leadingIcon

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meeting.displayTitle)
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        if !previewText.isEmpty {
                            Text(previewText)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.mutedInk)
                                .lineLimit(2)
                        }
                    }

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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AppGlassSurface(
                cornerRadius: 30,
                style: isRecording ? .regular : .clear,
                borderOpacity: isRecording ? 0.34 : 0.24,
                shadowOpacity: 0.10
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityIdentifier("MeetingRow")
        .onTapGesture(perform: onOpen)
    }

    private var leadingIcon: some View {
        ZStack(alignment: .topTrailing) {
            AppGlassSurface(cornerRadius: 22, style: .regular, shadowOpacity: 0.05)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }

            if isRecording {
                Circle()
                    .fill(AppTheme.highlight)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    }
                    .offset(x: 4, y: -4)
            }
        }
    }

    private func metadataPill(systemName: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))

            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(AppTheme.mutedInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            AppGlassSurface(cornerRadius: 15, style: .clear, shadowOpacity: 0.03)
        }
    }

    private var syncBadge: some View {
        Image(systemName: meeting.syncStateIconName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(syncForeground)
            .frame(width: 32, height: 32)
            .background {
                AppGlassSurface(cornerRadius: 16, style: .clear, shadowOpacity: 0.03)
            }
            .accessibilityLabel(meeting.syncStateLabel)
    }

    private var previewText: String {
        meeting.previewText.replacingOccurrences(of: "\n", with: " ")
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
