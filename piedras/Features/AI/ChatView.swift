import SwiftUI

struct ChatView: View {
    let meeting: Meeting

    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("会议内 AI 对话", systemImage: "message")
                .font(.headline)

            if meeting.orderedChatMessages.isEmpty {
                Text("后续接入 `/api/chat` 后，这里会显示单会议问答记录。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(meeting.orderedChatMessages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == "assistant" ? "AI" : "你")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(message.role == "assistant" ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            HStack(spacing: 8) {
                TextField("输入问题", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button("发送") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
