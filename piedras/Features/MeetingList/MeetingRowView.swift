import SwiftUI

struct MeetingRowSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let metadataLine: String
    let isRecording: Bool
    let showsSyncFailure: Bool

    init(meeting: Meeting, isRecording: Bool) {
        id = meeting.id
        title = meeting.displayTitle
        metadataLine = meeting.homeMetadataLine
        self.isRecording = isRecording
        showsSyncFailure = !isRecording && meeting.syncState == .failed
    }
}

struct MeetingRowView: View {
    let snapshot: MeetingRowSnapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                leadingIcon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(snapshot.title)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        if snapshot.isRecording {
                            RetroStampLabel(text: "REC")
                        } else if snapshot.showsSyncFailure {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }

                    Text(snapshot.metadataLine)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.subtleInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(
                        snapshot.isRecording ? AppTheme.highlight : AppTheme.border,
                        lineWidth: AppTheme.retroBorderWidth
                    )
            )
            .retroHardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("MeetingRow")
    }

    private var leadingIcon: some View {
        ZStack(alignment: .topTrailing) {
            RetroIconBadge(systemName: "doc.text", size: 44, symbolSize: 16)

            if snapshot.isRecording {
                Rectangle()
                    .fill(AppTheme.highlight)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.surface, lineWidth: 2)
                    )
                    .offset(x: 3, y: -3)
            }
        }
    }
}
