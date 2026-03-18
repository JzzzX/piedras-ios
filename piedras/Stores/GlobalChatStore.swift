import Foundation
import Observation

struct GlobalChatMessage: Identifiable, Hashable {
    let id: String
    let role: String
    var content: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        role: String,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class GlobalChatStore {
    private let apiClient: APIClient
    private let settingsStore: SettingsStore
    private let workspaceBootstrapService: WorkspaceBootstrapService

    var messages: [GlobalChatMessage] = []
    var isStreaming = false
    var lastErrorMessage: String?

    init(
        apiClient: APIClient,
        settingsStore: SettingsStore,
        workspaceBootstrapService: WorkspaceBootstrapService
    ) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.workspaceBootstrapService = workspaceBootstrapService
    }

    func sendMessage(_ question: String) async -> Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return false }
        guard !isStreaming else { return false }

        if let blockingMessage = settingsStore.blockingMessage(for: .ai) {
            lastErrorMessage = blockingMessage
            return false
        }

        lastErrorMessage = nil
        isStreaming = true

        let userMessage = GlobalChatMessage(role: "user", content: trimmedQuestion)
        let assistantMessageID = UUID().uuidString.lowercased()

        messages.append(userMessage)
        messages.append(GlobalChatMessage(id: assistantMessageID, role: "assistant", content: ""))

        defer { isStreaming = false }

        do {
            let workspaceID = try await resolveWorkspaceID()
            let payload = GlobalChatRequestPayload(
                question: trimmedQuestion,
                chatHistory: chatHistory(excludingAssistantMessageID: assistantMessageID),
                filters: .init(workspaceId: workspaceID)
            )
            let stream = try await apiClient.streamGlobalChat(payload)

            for try await partialContent in stream {
                guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
                    continue
                }
                messages[index].content = partialContent
            }

            if let index = messages.firstIndex(where: { $0.id == assistantMessageID }),
               messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].content = "当前没有返回内容。"
            }

            return true
        } catch {
            messages.removeAll(where: { $0.id == assistantMessageID })
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func resetConversation() {
        messages.removeAll()
        lastErrorMessage = nil
    }

    private func resolveWorkspaceID() async throws -> String? {
        if let workspaceID = settingsStore.hiddenWorkspaceID {
            return workspaceID
        }

        return try await workspaceBootstrapService.bootstrapHiddenWorkspace()
    }

    private func chatHistory(excludingAssistantMessageID assistantMessageID: String) -> [ChatHistoryPayload] {
        messages
            .filter { $0.id != assistantMessageID }
            .suffix(12)
            .map { ChatHistoryPayload(role: $0.role, content: $0.content) }
    }
}
