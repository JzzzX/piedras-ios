import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isRecording: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                leadingIcon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(meeting.displayTitle)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        if isRecording {
                            RetroStampLabel(text: "REC")
                        } else if meeting.syncState == .failed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }

                    Text(meeting.homeMetadataLine)
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
                        isRecording ? AppTheme.highlight : AppTheme.border,
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

            if isRecording {
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
