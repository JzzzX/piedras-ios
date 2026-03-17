import SwiftUI

struct GlobalChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GlobalChatStore.self) private var globalChatStore

    @State private var input = ""

    var body: some View {
        ZStack {
            AppTheme.pageGradient
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if globalChatStore.messages.isEmpty {
                            emptyState
                        } else {
                            messageList
                        }

                        if let error = globalChatStore.lastErrorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.danger)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            globalChatStore.resetConversation()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask anything")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("Search across your synced meeting memory without exposing workspace complexity in the UI.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            HStack(spacing: 10) {
                if !globalChatStore.messages.isEmpty {
                    Button {
                        globalChatStore.resetConversation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.surface, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.surface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about themes, decisions, action items, or how a topic evolved over time.")
                .font(.body)
                .foregroundStyle(AppTheme.mutedInk)

            HStack(spacing: 10) {
                suggestion("What did users dislike most?")
                suggestion("Summarize open decisions")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
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
        .background(isUser ? AppTheme.ink : AppTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                .background(AppTheme.backgroundSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Ask across your meeting history", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.65), lineWidth: 1)
                }

            Button {
                let question = input
                Task {
                    let sent = await globalChatStore.sendMessage(question)
                    if sent {
                        input = ""
                    }
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || globalChatStore.isStreaming)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }
}
