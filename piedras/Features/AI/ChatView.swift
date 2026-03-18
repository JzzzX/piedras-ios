import SwiftUI

struct ChatView: View {
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    let meeting: Meeting

    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("会议内 AI 对话", systemImage: "message")
                .font(.headline)

            if let blockingMessage {
                HStack(spacing: 10) {
                    Text(blockingMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Settings") {
                        router.showSettings()
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            if meeting.orderedChatMessages.isEmpty {
                Text("基于当前会议转写、用户笔记和 AI 总结做单会议问答。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(meeting.orderedChatMessages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == "assistant" ? "AI" : "你")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if message.content.isEmpty, message.role == "assistant", meetingStore.isStreamingChat(meetingID: meeting.id) {
                            ProgressView("正在生成回复...")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(message.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(message.role == "assistant" ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            HStack(spacing: 8) {
                TextField("输入问题", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isComposerBlocked)
                Button(meetingStore.isStreamingChat(meetingID: meeting.id) ? "发送中" : "发送") {
                    let question = input
                    Task {
                        let didSend = await meetingStore.sendChatMessage(question: question, for: meeting.id)
                        if didSend {
                            input = ""
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meetingStore.isStreamingChat(meetingID: meeting.id) || isComposerBlocked)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var blockingMessage: String? {
        settingsStore.blockingMessage(for: .ai)
    }

    private var isComposerBlocked: Bool {
        blockingMessage != nil
    }
}
