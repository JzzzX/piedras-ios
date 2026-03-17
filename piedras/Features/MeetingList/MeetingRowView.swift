import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isRecording: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if isRecording {
                            Circle()
                                .fill(AppTheme.highlight)
                                .frame(width: 8, height: 8)
                        }

                        Text(meeting.displayTitle)
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.leading)
                    }

                    Text(meeting.previewText.isEmpty ? "Transcript and smart notes will appear here as soon as the meeting has enough signal." : meeting.previewText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除会议", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(AppTheme.subtleInk)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.backgroundSecondary, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                metadataChip(
                    label: meeting.compactTimestampLabel,
                    systemImage: "calendar",
                    tint: AppTheme.backgroundSecondary,
                    foreground: AppTheme.mutedInk
                )
                metadataChip(
                    label: meeting.durationLabel,
                    systemImage: "clock",
                    tint: AppTheme.backgroundSecondary,
                    foreground: AppTheme.mutedInk
                )
                metadataChip(
                    label: meeting.transcriptSummaryLabel,
                    systemImage: "text.quote",
                    tint: AppTheme.accentSoft,
                    foreground: AppTheme.accent
                )
                Spacer()
                syncBadge
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isRecording ? AppTheme.surfaceElevated : AppTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isRecording ? AppTheme.highlight.opacity(0.45) : AppTheme.border.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: AppTheme.cardShadow, radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private func metadataChip(label: String, systemImage: String, tint: Color, foreground: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }

    private var syncBadge: some View {
        Text(meeting.syncStateLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(syncForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(syncBackground, in: Capsule())
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

    private var syncBackground: Color {
        switch meeting.syncState {
        case .pending:
            return AppTheme.highlightSoft
        case .syncing:
            return AppTheme.accentSoft
        case .synced:
            return AppTheme.success.opacity(0.14)
        case .failed:
            return AppTheme.danger.opacity(0.12)
        case .deleted:
            return AppTheme.backgroundSecondary
        }
    }
}
