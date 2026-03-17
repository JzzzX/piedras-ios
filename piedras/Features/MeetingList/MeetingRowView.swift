import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(meeting.syncStateLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(meeting.syncStateTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(meeting.syncStateTint.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                Label(meeting.durationLabel, systemImage: "clock")
                Label("\(meeting.orderedSegments.count) 段", systemImage: "text.quote")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !meeting.previewText.isEmpty {
                Text(meeting.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
