import SwiftUI

struct TranscriptView: View {
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        List {
            if recordingSessionStore.meetingID == meeting.id && !recordingSessionStore.currentPartial.isEmpty {
                Section("实时结果") {
                    Text(recordingSessionStore.currentPartial)
                        .foregroundStyle(.secondary)
                }
            }

            if meeting.orderedSegments.isEmpty {
                ContentUnavailableView(
                    "还没有转写内容",
                    systemImage: "text.quote",
                    description: Text("后续接入实时转写后，这里会显示 partial 和 final transcript。")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(meeting.orderedSegments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(segment.speaker)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(segment.timeRangeLabel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Text(segment.text)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
}
