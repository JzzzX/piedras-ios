import Foundation

@MainActor
final class WorkspaceBootstrapService {
    private enum Constants {
        static let hiddenWorkspaceName = "Piedras iOS"
        static let hiddenWorkspaceDescription = "Piedras iOS MVP 隐藏工作区"
        static let hiddenWorkspaceIcon = "iphone"
        static let hiddenWorkspaceColor = "#0f766e"
    }

    private let apiClient: APIClient
    private let settingsStore: SettingsStore

    init(apiClient: APIClient, settingsStore: SettingsStore) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
    }

    @discardableResult
    func bootstrapHiddenWorkspace() async throws -> String {
        settingsStore.workspaceBootstrapState = .loading
        settingsStore.workspaceStatusMessage = "正在检查工作区..."

        let workspaces = try await apiClient.listWorkspaces()
        settingsStore.markBackendReachable()

        if let currentID = settingsStore.hiddenWorkspaceID,
           workspaces.contains(where: { $0.id == currentID }) {
            settingsStore.workspaceBootstrapState = .success
            settingsStore.workspaceStatusMessage = "已复用隐藏工作区"
            return currentID
        }

        if let existing = workspaces.first(where: { $0.name == Constants.hiddenWorkspaceName }) {
            settingsStore.hiddenWorkspaceID = existing.id
            settingsStore.workspaceBootstrapState = .success
            settingsStore.workspaceStatusMessage = "已找到现有隐藏工作区"
            return existing.id
        }

        let created = try await apiClient.createWorkspace(
            WorkspaceCreatePayload(
                name: Constants.hiddenWorkspaceName,
                description: Constants.hiddenWorkspaceDescription,
                icon: Constants.hiddenWorkspaceIcon,
                color: Constants.hiddenWorkspaceColor,
                workflowMode: "general",
                modeLabel: "iOS"
            )
        )

        settingsStore.hiddenWorkspaceID = created.id
        settingsStore.workspaceBootstrapState = .success
        settingsStore.workspaceStatusMessage = "已创建隐藏工作区"
        return created.id
    }
}
