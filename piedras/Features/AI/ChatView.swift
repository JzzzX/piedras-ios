import SwiftUI

struct MeetingChatEmptyStateContent {
    let scopeHint: String
    let prompt: String
    let suggestions: [String]
    let composerPlaceholder: String

    static func noteScoped(strings: AppStringTable = AppStrings.current) -> Self {
        .init(
            scopeHint: strings.meetingChatScopeHint,
            prompt: strings.meetingChatEmptyPrompt,
            suggestions: [
                strings.meetingChatSuggestSummarize,
                strings.meetingChatSuggestNextSteps,
            ],
            composerPlaceholder: strings.meetingChatComposerPlaceholder
        )
    }
}

struct ChatView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    let meeting: Meeting

    @State private var input = ""
    @State private var showHistoryDrawer = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                actionsBar
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if currentMessages.isEmpty {
                            emptyState
                        } else {
                            messageList
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 120)
                }
                .onChange(of: currentMessages.last?.id, initial: true) { _, lastID in
                    if let lastID {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .dismissKeyboardOnTap(isFocused: $isInputFocused)
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .overlay {
            ChatHistoryDrawerView(
                isPresented: $showHistoryDrawer,
                sections: historySections,
                activeSessionID: meetingStore.activeChatSession(for: meeting.id)?.id,
                scopeIcon: "doc.text",
                isInteractionDisabled: meetingStore.isStreamingChat(meetingID: meeting.id),
                onSelect: { sessionID in
                    meetingStore.activateChatSession(sessionID, for: meeting.id)
                },
                onDelete: { sessionID in
                    meetingStore.deleteChatSession(sessionID, for: meeting.id)
                },
                onNewChat: {
                    meetingStore.startNewChatDraft(for: meeting.id)
                }
            )
        }
        .task(id: meeting.id) {
            meetingStore.prepareChatSessions(for: meeting.id)
        }
        .id(settingsStore.appLanguage)
    }

    private var messageList: some View {
        VStack(spacing: 22) {
            ForEach(currentMessages) { message in
                messageRow(message)
                    .id(message.id)
            }
        }
    }

    private var actionsBar: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                AppGlassCircleButton(
                    systemName: "arrow.clockwise",
                    accessibilityLabel: AppStrings.current.regenerateAnswer,
                    size: 36
                ) {
                    Task {
                        _ = await meetingStore.regenerateLastChatResponse(for: meeting.id)
                    }
                }
                .accessibilityIdentifier("MeetingChatRegenerateButton")
                .disabled(!meetingStore.canRegenerateLastChatResponse(for: meeting.id))

                AppGlassCircleButton(
                    systemName: "plus",
                    accessibilityLabel: AppStrings.current.newChat,
                    size: 36
                ) {
                    meetingStore.startNewChatDraft(for: meeting.id)
                }
                .accessibilityIdentifier("MeetingChatNewSessionButton")
                .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))

                ZStack(alignment: .topTrailing) {
                    AppGlassCircleButton(
                        systemName: "clock.arrow.circlepath",
                        accessibilityLabel: historyButtonAccessibilityLabel,
                        size: 36
                    ) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showHistoryDrawer = true
                        }
                    }
                    .accessibilityIdentifier("MeetingChatHistoryButton")
                    .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))

                    SessionCountBadge(count: historySessions.count)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emptyStateContent.prompt)
                .font(AppTheme.bodyFont(size: 15))
                .foregroundStyle(AppTheme.mutedInk)

            HStack(spacing: 10) {
                ForEach(emptyStateContent.suggestions, id: \.self) { suggestion in
                    suggestionButton(suggestion)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            input = text
            isInputFocused = true
        } label: {
            Text(text)
                .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))
    }

    private var emptyStateContent: MeetingChatEmptyStateContent {
        .noteScoped(strings: AppStrings.current)
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
                if isUser {
                    Text(message.content)
                        .font(AppTheme.bodyFont(size: 16))
                        .lineSpacing(AppTheme.editorialBodyLineSpacing)
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    ChatMarkdownMessageView(
                        markdown: message.content,
                        accessibilityIdentifier: "MeetingChatAssistantMessage"
                    )
                }
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

                    TextField(emptyStateContent.composerPlaceholder, text: $input)
                        .textFieldStyle(.plain)
                        .font(AppTheme.bodyFont(size: 15))
                        .foregroundStyle(AppTheme.ink)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit(sendCurrentInput)
                        .disabled(meetingStore.isStreamingChat(meetingID: meeting.id))
                        .accessibilityIdentifier("MeetingChatComposerField")
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                )

                Button(action: sendCurrentInput) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.surface)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.ink)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("MeetingChatComposerSendButton")
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

    private var historySections: [ChatSessionHistorySection] {
        ChatSessionHistorySection.makeSections(from: historySessions)
    }

    private var currentMessages: [ChatMessage] {
        meetingStore.chatMessages(for: meeting.id)
    }

    private var historySessions: [ChatSession] {
        meetingStore.chatSessions(for: meeting.id)
    }

    private var historyButtonAccessibilityLabel: String {
        SessionCountBadge.historyButtonAccessibilityLabel(
            baseLabel: AppStrings.current.chatHistoryTitle,
            count: historySessions.count
        )
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
