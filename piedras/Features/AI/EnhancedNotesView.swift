import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 总结", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button(meetingStore.isEnhancing(meetingID: meeting.id) ? "生成中" : "生成") {
                    Task {
                        await meetingStore.generateEnhancedNotes(for: meeting.id)
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(meetingStore.isEnhancing(meetingID: meeting.id) || !canGenerate)
            }

            if meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if meetingStore.isEnhancing(meetingID: meeting.id) {
                    ProgressView("正在生成结构化纪要...")
                } else {
                    Text("点击生成后，将调用 `/api/enhance` 输出结构化会议总结。")
                        .foregroundStyle(.secondary)
                }
            } else {
                if let markdown = try? AttributedString(markdown: meeting.enhancedNotes) {
                    Text(markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(meeting.enhancedNotes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var canGenerate: Bool {
        !meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
