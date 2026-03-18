import SwiftUI

struct ChatView: View {
    @Environment(MeetingStore.self) private var meetingStore

    let meeting: Meeting

    @State private var input = ""

    var body: some View {
        ZStack {
            DocumentBackdrop()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if meeting.orderedChatMessages.isEmpty {
                            emptyState
                        } else {
                            messageList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .onChange(of: meeting.orderedChatMessages.count, initial: false) { _, _ in
                    if let lastID = meeting.orderedChatMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask about this note")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Text("Transcript, notes and AI summary stay in context.")
                .font(.body)
                .foregroundStyle(AppTheme.subtleInk)

            HStack(spacing: 10) {
                suggestion("Summarize decisions")
                suggestion("List next steps")
            }
        }
    }

    private var messageList: some View {
        VStack(spacing: 12) {
            ForEach(meeting.orderedChatMessages) { message in
                HStack {
                    if message.role == "assistant" {
                        messageBubble(message, isUser: false)
                        Spacer(minLength: 46)
                    } else {
                        Spacer(minLength: 46)
                        messageBubble(message, isUser: true)
                    }
                }
                .id(message.id)
            }
        }
    }

    private func messageBubble(_ message: ChatMessage, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isUser ? "You" : "Piedras")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isUser ? Color.white.opacity(0.74) : AppTheme.subtleInk)

            if message.content.isEmpty, !isUser, meetingStore.isStreamingChat(meetingID: meeting.id) {
                ProgressView()
                    .tint(AppTheme.documentOlive)
            } else {
                Text(message.content)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(isUser ? .white : AppTheme.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isUser {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.ink)
            } else {
                PaperSurface(
                    cornerRadius: 22,
                    fill: AppTheme.documentPaper,
                    border: AppTheme.documentHairline,
                    shadowOpacity: 0.04
                )
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.subtleInk)

                TextField("Ask about this note", text: $input)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.ink)
                    .submitLabel(.send)
                    .onSubmit(sendCurrentInput)
                    .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background {
                PaperSurface(
                    cornerRadius: 24,
                    fill: AppTheme.documentPaper,
                    border: AppTheme.documentHairline,
                    shadowOpacity: 0.06
                )
            }

            Button(action: sendCurrentInput) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmedInput.isEmpty || meetingStore.isStreamingChat(meetingID: meeting.id))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            input = text
        } label: {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    PaperSurface(
                        cornerRadius: 18,
                        fill: AppTheme.documentPaperSecondary,
                        border: AppTheme.documentHairline,
                        shadowOpacity: 0.03
                    )
                }
        }
        .buttonStyle(.plain)
        .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendCurrentInput() {
        let question = trimmedInput
        guard !question.isEmpty else { return }

        Task {
            let didSend = await meetingStore.sendChatMessage(question: question, for: meeting.id)
            if didSend {
                input = ""
            }
        }
    }
}
