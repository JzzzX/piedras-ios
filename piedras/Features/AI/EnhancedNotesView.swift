import SwiftUI

struct EnhancedNotesView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 总结", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button("生成") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }

            if meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("后续接入 `/api/enhance` 后，这里会展示结构化会议总结。")
                    .foregroundStyle(.secondary)
            } else {
                Text(meeting.enhancedNotes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
