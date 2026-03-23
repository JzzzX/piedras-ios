import Foundation
import Observation

enum GlobalChatPhase {
    case idle
    case preparing
    case streaming
    case failed
}

@MainActor
@Observable
final class GlobalChatStore {
    private let apiClient: APIClient
    private let settingsStore: SettingsStore
    private let workspaceBootstrapService: WorkspaceBootstrapService
    private let chatSessionRepository: ChatSessionRepository

    var sessions: [ChatSession] = []
    var messages: [ChatMessage] = []
    var activeSessionID: String?
    var phase: GlobalChatPhase = .idle
    var statusMessage: String?
    var lastErrorMessage: String?

    var isStreaming: Bool {
        phase == .streaming
    }

    init(
        apiClient: APIClient,
        settingsStore: SettingsStore,
        workspaceBootstrapService: WorkspaceBootstrapService,
        chatSessionRepository: ChatSessionRepository
    ) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.workspaceBootstrapService = workspaceBootstrapService
        self.chatSessionRepository = chatSessionRepository
        reloadSessions(selectMostRecentIfNeeded: true)
    }

    func sendMessage(_ question: String) async -> Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return false }
        guard phase != .streaming else { return false }

        lastErrorMessage = nil
        statusMessage = "AI 正在生成"
        phase = .streaming

        let session = ensureActiveSession()
        let history = chatHistory(for: session)
        let userMessage = chatSessionRepository.appendUserMessage(trimmedQuestion, to: session)
        let assistantMessage = chatSessionRepository.appendAssistantPlaceholder(to: session)
        try? chatSessionRepository.save()
        activeSessionID = session.id
        reloadSessions(selectMostRecentIfNeeded: false)
        messages = session.orderedMessages

        defer {
            if phase != .failed {
                phase = .idle
            }
        }

        do {
            let workspaceID = try await resolveWorkspaceID()
            let payload = GlobalChatRequestPayload(
                question: trimmedQuestion,
                chatHistory: history,
                filters: .init(workspaceId: workspaceID)
            )
            let stream = try await apiClient.streamGlobalChat(payload)

            for try await partialContent in stream {
                assistantMessage.content = partialContent
            }

            if assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                assistantMessage.content = "当前没有返回内容。"
            }

            session.updatedAt = max(userMessage.timestamp, .now)
            try? chatSessionRepository.save()
            reloadSessions(selectMostRecentIfNeeded: false)
            messages = session.orderedMessages
            statusMessage = nil
            settingsStore.markLLMRequestSucceeded()
            return true
        } catch {
            session.messages.removeAll(where: { $0.id == assistantMessage.id })
            lastErrorMessage = error.localizedDescription
            statusMessage = nil
            phase = .failed
            try? chatSessionRepository.save()
            reloadSessions(selectMostRecentIfNeeded: false)
            messages = session.orderedMessages
            settingsStore.markLLMRequestFailed(message: error.localizedDescription)
            return false
        }
    }

    func beginPreparing() {
        lastErrorMessage = nil
        statusMessage = "正在检查 AI 服务"
        phase = .preparing
    }

    func finishPreparing() {
        if phase == .preparing {
            statusMessage = nil
            phase = .idle
        }
    }

    func failPreparing(message: String) {
        lastErrorMessage = message
        statusMessage = nil
        phase = .failed
    }

    func startNewDraft() {
        lastErrorMessage = nil
        statusMessage = nil
        phase = .idle
        activeSessionID = nil
        messages = []
        reloadSessions(selectMostRecentIfNeeded: false)
    }

    func activateSession(_ sessionID: String) {
        guard phase != .streaming else { return }
        lastErrorMessage = nil
        activeSessionID = sessionID
        reloadSessions(selectMostRecentIfNeeded: false)
    }

    func deleteSession(_ sessionID: String) {
        guard phase != .streaming else { return }
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }

        do {
            try chatSessionRepository.delete(session)
            let wasActive = activeSessionID == sessionID
            lastErrorMessage = nil
            reloadSessions(selectMostRecentIfNeeded: false)
            if wasActive {
                activeSessionID = sessions.first?.id
                messages = sessions.first?.orderedMessages ?? []
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetConversation() {
        startNewDraft()
    }

    private func resolveWorkspaceID() async throws -> String? {
        if let workspaceID = settingsStore.hiddenWorkspaceID {
            return workspaceID
        }

        return try await workspaceBootstrapService.bootstrapHiddenWorkspace()
    }

    private func ensureActiveSession() -> ChatSession {
        if let activeSession = activeSession {
            return activeSession
        }

        let session = chatSessionRepository.makeDraftSession(scope: .global, meeting: nil)
        activeSessionID = session.id
        return session
    }

    private var activeSession: ChatSession? {
        sessions.first(where: { $0.id == activeSessionID })
    }

    private func chatHistory(for session: ChatSession) -> [ChatHistoryPayload] {
        session.orderedMessages
            .suffix(12)
            .map { ChatHistoryPayload(role: $0.role, content: $0.content) }
    }

    private func reloadSessions(selectMostRecentIfNeeded: Bool) {
        sessions = (try? chatSessionRepository.fetchSessions(scope: .global)) ?? []
        if selectMostRecentIfNeeded, activeSessionID == nil {
            activeSessionID = sessions.first?.id
            messages = sessions.first?.orderedMessages ?? []
        } else if let activeSession {
            messages = activeSession.orderedMessages
        } else {
            messages = []
        }
    }
}
