import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let backendBaseURLString = "piedras.settings.backendBaseURLString"
        static let hiddenWorkspaceID = "piedras.settings.hiddenWorkspaceID"
    }

    private let defaults: UserDefaults

    var backendBaseURLString: String {
        didSet {
            defaults.set(backendBaseURLString, forKey: Key.backendBaseURLString)
        }
    }

    var hiddenWorkspaceID: String? {
        didSet {
            defaults.set(hiddenWorkspaceID, forKey: Key.hiddenWorkspaceID)
        }
    }

    var apiReachable = false
    var asrReady = false
    var llmReady = false
    var lastHealthCheckAt: Date?
    var workspaceBootstrapState: WorkspaceBootstrapState = .idle
    var backendStatusMessage = "未检查"
    var asrStatusMessage = "未检查"
    var llmStatusMessage = "未检查"
    var llmProvider = "none"
    var llmModel: String?
    var llmPreset: String?
    var workspaceStatusMessage = "尚未初始化"
    var syncStatusMessage = ""
    var isCheckingHealth = false
    var isSyncing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backendBaseURLString = defaults.string(forKey: Key.backendBaseURLString) ?? "http://127.0.0.1:3000"
        hiddenWorkspaceID = defaults.string(forKey: Key.hiddenWorkspaceID)
    }

    var backendBaseURL: URL? {
        URL(string: backendBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum WorkspaceBootstrapState: String {
    case idle
    case loading
    case success
    case failed
}
