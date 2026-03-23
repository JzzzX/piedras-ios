import SwiftUI

struct ChatView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    let meeting: Meeting

    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
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
        .id(settingsStore.appLanguage)
    }

    private var messageList: some View {
        VStack(spacing: 22) {
            ForEach(meeting.orderedChatMessages) { message in
                messageRow(message)
                    .id(message.id)
            }
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let isUser = message.role == "user"

        return VStack(alignment: .leading, spacing: 10) {
            Text(isUser ? "YOU>" : "AI>")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.subtleInk)

            if message.content.isEmpty, !isUser, meetingStore.isStreamingChat(meetingID: meeting.id) {
                HStack(spacing: 4) {
                    RetroBlinkingCursor()
                    Text(AppStrings.current.processing)
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundStyle(AppTheme.subtleInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(message.content)
                    .font(AppTheme.bodyFont(size: 16))
                    .lineSpacing(AppTheme.editorialBodyLineSpacing)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            ThinDivider()

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text(">")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.subtleInk)

                    TextField(AppStrings.current.chatWithNote, text: $input)
                        .textFieldStyle(.plain)
                        .font(AppTheme.bodyFont(size: 15))
                        .foregroundStyle(AppTheme.ink)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit(sendCurrentInput)
                        .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))
                        .accessibilityIdentifier("MeetingChatComposerField")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)

                Button(action: sendCurrentInput) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.surface)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.ink)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                }
                .buttonStyle(.plain)
                .disabled(trimmedInput.isEmpty || meetingStore.isStreamingChat(meetingID: meeting.id))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(AppTheme.surface)
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
