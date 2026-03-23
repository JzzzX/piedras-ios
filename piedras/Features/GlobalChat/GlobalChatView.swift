import SwiftUI

struct GlobalChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(GlobalChatStore.self) private var globalChatStore
    @Environment(SettingsStore.self) private var settingsStore

    let initialQuestion: String?

    @State private var input = ""
    @State private var didSendInitialQuestion = false
    @State private var showHistoryDrawer = false
    @FocusState private var isInputFocused: Bool

    init(initialQuestion: String? = nil) {
        self.initialQuestion = initialQuestion
    }

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if let availabilityMessage {
                            statusBanner(availabilityMessage)
                        } else if let statusMessage = globalChatStore.statusMessage {
                            statusBanner(statusMessage)
                        }

                        if globalChatStore.messages.isEmpty {
                            emptyState
                        } else {
                            messageList
                        }

                        if let error = globalChatStore.lastErrorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                .onChange(of: globalChatStore.messages.last?.id, initial: true) { _, lastID in
                    if let lastID {
                        withAnimation(.easeOut(duration: 0.2)) {
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
                activeSessionID: globalChatStore.activeSessionID,
                scopeIcon: "globe",
                isInteractionDisabled: globalChatStore.phase != .idle,
                onSelect: { sessionID in
                    globalChatStore.activateSession(sessionID)
                },
                onDelete: { sessionID in
                    globalChatStore.deleteSession(sessionID)
                },
                onNewChat: {
                    globalChatStore.startNewDraft()
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await meetingStore.checkBackendHealth(force: false)
        }
        .task(id: initialQuestion) {
            guard !didSendInitialQuestion else { return }
            let question = initialQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !question.isEmpty else { return }
            didSendInitialQuestion = true

            if await prepareAIRequest() {
                _ = await globalChatStore.sendMessage(question)
            } else {
                input = question
            }
        }
        .id(settingsStore.appLanguage)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.current.ask)
                    .font(AppTheme.bodyFont(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                Text(AppStrings.current.allNotes)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            HStack(spacing: 8) {
                AppGlassCircleButton(
                    systemName: "plus",
                    accessibilityLabel: AppStrings.current.newChat,
                    size: 36
                ) {
                    globalChatStore.startNewDraft()
                }
                .disabled(globalChatStore.phase != .idle)

                ZStack(alignment: .topTrailing) {
                    AppGlassCircleButton(
                        systemName: "clock.arrow.circlepath",
                        accessibilityLabel: AppStrings.current.chatHistoryTitle,
                        size: 36
                    ) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showHistoryDrawer = true
                        }
                    }
                    .disabled(globalChatStore.phase != .idle)

                    SessionCountBadge(count: globalChatStore.sessions.count)
                }

                AppGlassCircleButton(
                    systemName: "xmark",
                    accessibilityLabel: AppStrings.current.close,
                    size: 36
                ) {
                    dismiss()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.current.askFromTranscript)
                .font(AppTheme.bodyFont(size: 15))
                .foregroundStyle(AppTheme.mutedInk)

            HStack(spacing: 10) {
                suggestion(AppStrings.current.suggestSummarize)
                suggestion(AppStrings.current.suggestChanged)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private var messageList: some View {
        VStack(spacing: 12) {
            ForEach(globalChatStore.messages) { message in
                HStack {
                    if message.role == "assistant" {
                        chatBubble(message: message, isUser: false)
                        Spacer(minLength: 40)
                    } else {
                        Spacer(minLength: 40)
                        chatBubble(message: message, isUser: true)
                    }
                }
                .id(message.id)
            }
        }
    }

    private func chatBubble(message: ChatMessage, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isUser ? "YOU>" : "PIEDRAS>")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isUser ? AppTheme.surface.opacity(0.72) : AppTheme.subtleInk)

            if message.content.isEmpty && !isUser && globalChatStore.isStreaming {
                HStack(spacing: 4) {
                    RetroBlinkingCursor()
                    Text(AppStrings.current.processing)
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundStyle(AppTheme.subtleInk)
                }
            } else {
                Text(message.content)
                    .font(AppTheme.bodyFont(size: 15))
                    .lineSpacing(AppTheme.editorialBodyLineSpacing)
                    .foregroundStyle(isUser ? .white : AppTheme.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUser ? AppTheme.ink : AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            input = text
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
        .disabled(isComposerBlocked)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(">")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)

                TextField(AppStrings.current.askAcrossMeetings, text: $input)
                    .textFieldStyle(.plain)
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.ink)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendCurrentInput)
                    .accessibilityIdentifier("GlobalChatInputField")
                    .disabled(isComposerBlocked)
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
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedInput.isEmpty || globalChatStore.isStreaming || isComposerBlocked)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(AppTheme.background)
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.subtleInk)

            Text(message)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(AppStrings.current.settings) {
                router.showSettings()
            }
            .buttonStyle(.plain)
            .font(AppTheme.bodyFont(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(AppTheme.bodyFont(size: 13))
            .foregroundStyle(AppTheme.danger)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.danger.opacity(0.08))
            .overlay(
                Rectangle()
                    .stroke(AppTheme.danger, lineWidth: AppTheme.retroBorderWidth)
            )
    }

    private var availabilityMessage: String? {
        settingsStore.blockingMessage(for: .ai)
    }

    private var isComposerBlocked: Bool {
        availabilityMessage != nil || globalChatStore.phase == .preparing
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var historySections: [ChatSessionHistorySection] {
        ChatSessionHistorySection.makeSections(from: globalChatStore.sessions)
    }

    private func sendCurrentInput() {
        let question = trimmedInput
        guard !question.isEmpty else { return }

        isInputFocused = false
        hideKeyboard()
        Task {
            guard await prepareAIRequest() else { return }
            let sent = await globalChatStore.sendMessage(question)
            if sent {
                input = ""
            }
        }
    }

    private func prepareAIRequest() async -> Bool {
        globalChatStore.beginPreparing()
        let isReady = await meetingStore.prepareAI(force: false)

        guard isReady else {
            let message = settingsStore.blockingMessage(for: .ai)
                ?? (settingsStore.llmStatusMessage.isEmpty
                    ? "\(AppEnvironment.cloudName) 暂时不可用。"
                    : settingsStore.llmStatusMessage)
            globalChatStore.failPreparing(message: message)
            return false
        }

        globalChatStore.finishPreparing()
        return true
    }
}
