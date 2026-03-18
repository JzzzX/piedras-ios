import SwiftUI

struct ChatView: View {
    @Environment(MeetingStore.self) private var meetingStore

    let meeting: Meeting

    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if meeting.orderedChatMessages.isEmpty {
                        Color.clear
                            .frame(height: 8)
                    } else {
                        messageList
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 120)
            }
                .onChange(of: meeting.orderedChatMessages.count, initial: false) { _, _ in
                    if let lastID = meeting.orderedChatMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap(isFocused: $isInputFocused)
        .safeAreaInset(edge: .bottom) {
            composer
        }
    }

    private var messageList: some View {
        VStack(spacing: 28) {
            ForEach(meeting.orderedChatMessages) { message in
                messageRow(message)
                    .id(message.id)
            }
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let isUser = message.role == "user"

        return VStack(alignment: .leading, spacing: 10) {
            Text(isUser ? "You" : "AI")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.subtleInk)

            if message.content.isEmpty, !isUser, meetingStore.isStreamingChat(meetingID: meeting.id) {
                ProgressView()
                    .tint(AppTheme.documentOlive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(message.content)
                    .font(AppTheme.editorialFont(size: 20))
                    .lineSpacing(AppTheme.editorialBodyLineSpacing)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.subtleInk)

                TextField("Ask about this note", text: $input)
                    .textFieldStyle(.plain)
                    .font(AppTheme.editorialFont(size: 18))
                    .foregroundStyle(AppTheme.ink)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendCurrentInput)
                    .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background {
                AppGlassSurface(cornerRadius: 27, style: .clear, borderOpacity: 0.20, shadowOpacity: 0.08)
                    .clipShape(Capsule())
            }

            Button(action: sendCurrentInput) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 50, height: 50)
                    .background {
                        AppGlassSurface(cornerRadius: 25, style: .clear, borderOpacity: 0.18, shadowOpacity: 0.08)
                            .clipShape(Circle())
                    }
            }
            .buttonStyle(.plain)
            .disabled(trimmedInput.isEmpty || meetingStore.isStreamingChat(meetingID: meeting.id))
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.clear)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendCurrentInput() {
        let question = trimmedInput
        guard !question.isEmpty else { return }

        isInputFocused = false
        hideKeyboard()
        Task {
            let didSend = await meetingStore.sendChatMessage(question: question, for: meeting.id)
            if didSend {
                input = ""
            }
        }
    }
}
