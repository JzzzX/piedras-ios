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
                .onChange(of: globalChatStore.messages.count, initial: false) { _, _ in
                    if let lastID = globalChatStore.messages.last?.id {
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
        .onDisappear {
            globalChatStore.resetConversation()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("All notes")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            HStack(spacing: 10) {
                if !globalChatStore.messages.isEmpty {
                    AppGlassCircleButton(systemName: "arrow.counterclockwise", accessibilityLabel: "重置对话") {
                        globalChatStore.resetConversation()
                    }
                }

                AppGlassCircleButton(systemName: "xmark", accessibilityLabel: "关闭") {
                    dismiss()
                }
            }
        }
    }

    private var emptyState: some View {
        AppGlassCard(cornerRadius: 30, style: .regular, padding: 20, shadowOpacity: 0.06) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask from transcript, notes and summaries.")
                    .font(.body)
                    .foregroundStyle(AppTheme.mutedInk)

                HStack(spacing: 10) {
                    suggestion("Summarize open decisions")
                    suggestion("What changed most?")
                }
            }
        }
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

    private func chatBubble(message: GlobalChatMessage, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isUser ? "You" : "Piedras")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isUser ? Color.white.opacity(0.72) : AppTheme.subtleInk)

            if message.content.isEmpty && !isUser && globalChatStore.isStreaming {
                ProgressView()
                    .tint(AppTheme.accent)
            } else {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(isUser ? .white : AppTheme.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isUser ? AppTheme.ink : AppTheme.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            if !isUser {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
            }
        }
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
                    AppGlassSurface(cornerRadius: 18, style: .clear, shadowOpacity: 0.03)
                }
        }
        .buttonStyle(.plain)
        .disabled(isComposerBlocked)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.subtleInk)

                TextField("Ask across your meetings", text: $input)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.ink)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendCurrentInput)
                    .accessibilityIdentifier("GlobalChatInputField")
                    .disabled(isComposerBlocked)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background {
                AppGlassSurface(cornerRadius: 22, style: .clear, borderOpacity: 0.20, shadowOpacity: 0.06)
                    .clipShape(Capsule())
            }

            Button(action: sendCurrentInput) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmedInput.isEmpty || globalChatStore.isStreaming || isComposerBlocked)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.subtleInk)

            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Settings") {
                router.showSettings()
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AppGlassSurface(cornerRadius: 18, style: .clear, shadowOpacity: 0.03)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.danger)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
