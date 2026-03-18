import Foundation
import Observation

enum BackendConnectionState {
    case unconfigured
    case configuredUnchecked
    case reachable
    case unreachable
}

enum RemoteCapabilityKind {
    case backend
    case ai
    case asr
    case sync
}

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let backendBaseURLString = "piedras.settings.backendBaseURLString"
        static let hiddenWorkspaceID = "piedras.settings.hiddenWorkspaceID"
        static let lastSuccessfulBackendURLString = "piedras.settings.lastSuccessfulBackendURLString"
    }

    private let defaults: UserDefaults

    var backendBaseURLString: String {
        didSet {
            defaults.set(backendBaseURLString, forKey: Key.backendBaseURLString)

            guard normalized(backendBaseURLString) != normalized(oldValue) else {
                return
            }

            hiddenWorkspaceID = nil
            workspaceBootstrapState = .idle
            workspaceStatusMessage = "等待连接后端"
            resetRemoteStatus()
        }
    }

    var hiddenWorkspaceID: String? {
        didSet {
            defaults.set(hiddenWorkspaceID, forKey: Key.hiddenWorkspaceID)
        }
    }

    var lastSuccessfulBackendURLString: String? {
        didSet {
            defaults.set(lastSuccessfulBackendURLString, forKey: Key.lastSuccessfulBackendURLString)
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

    init(defaults: UserDefaults = .standard, defaultBackendBaseURLString: String = "") {
        self.defaults = defaults
        let storedBackendURLString = defaults.string(forKey: Key.backendBaseURLString)
        let storedLastSuccessfulBackendURLString = defaults.string(forKey: Key.lastSuccessfulBackendURLString)
        let migratedBackendURLString: String

        if storedBackendURLString == Self.simulatorLoopbackBaseURLString,
           (storedLastSuccessfulBackendURLString ?? "").isEmpty,
           defaultBackendBaseURLString.isEmpty {
            migratedBackendURLString = ""
        } else {
            migratedBackendURLString = storedBackendURLString ?? defaultBackendBaseURLString
        }

        backendBaseURLString = migratedBackendURLString
        hiddenWorkspaceID = defaults.string(forKey: Key.hiddenWorkspaceID)
        lastSuccessfulBackendURLString = storedLastSuccessfulBackendURLString

        if hasConfiguredBackendURL {
            backendStatusMessage = "Connection not checked"
            asrStatusMessage = "Check the server first"
            llmStatusMessage = "Check the server first"
            workspaceStatusMessage = "等待连接后端"
        } else {
            markBackendUnconfigured()
        }
    }

    var backendBaseURL: URL? {
        guard hasConfiguredBackendURL else {
            return nil
        }

        return URL(string: trimmedBackendBaseURLString)
    }

    var trimmedBackendBaseURLString: String {
        normalized(backendBaseURLString)
    }

    var hasConfiguredBackendURL: Bool {
        !trimmedBackendBaseURLString.isEmpty
    }

    var requiresInitialBackendSetup: Bool {
        !hasConfiguredBackendURL
    }

    var backendConnectionState: BackendConnectionState {
        if !hasConfiguredBackendURL {
            return .unconfigured
        }

        if apiReachable {
            return .reachable
        }

        if lastHealthCheckAt == nil {
            return .configuredUnchecked
        }

        return .unreachable
    }

    func blockingMessage(for capability: RemoteCapabilityKind) -> String? {
        if !hasConfiguredBackendURL {
            switch capability {
            case .backend:
                return "Set your Mac backend address in Settings."
            case .ai:
                return "Set your Mac backend address in Settings to use AI."
            case .asr:
                return "Set your Mac backend address in Settings to enable live transcription."
            case .sync:
                return "Set your Mac backend address in Settings before syncing."
            }
        }

        if lastHealthCheckAt != nil, !apiReachable {
            switch capability {
            case .backend, .sync:
                return "Backend offline. Start ai_notepad on your Mac or update the server address in Settings."
            case .ai:
                return "Backend offline. Start ai_notepad on your Mac or update the server address in Settings."
            case .asr:
                return "Backend offline. Live transcription is unavailable until ai_notepad is running."
            }
        }

        switch capability {
        case .ai:
            if lastHealthCheckAt != nil, apiReachable, !llmReady {
                return "AI unavailable. Check the backend LLM status in Settings."
            }
        case .asr:
            if lastHealthCheckAt != nil, apiReachable, !asrReady {
                return "Transcription unavailable. Check the backend ASR status in Settings."
            }
        case .backend, .sync:
            break
        }

        return nil
    }

    func markBackendUnconfigured() {
        apiReachable = false
        asrReady = false
        llmReady = false
        lastHealthCheckAt = nil
        backendStatusMessage = "Backend not configured"
        asrStatusMessage = "Add a server first"
        llmStatusMessage = "Add a server first"
        llmProvider = "none"
        llmModel = nil
        llmPreset = nil
    }

    func markBackendReachable(message: String = "Backend online") {
        apiReachable = true
        backendStatusMessage = message
        lastHealthCheckAt = .now
        lastSuccessfulBackendURLString = trimmedBackendBaseURLString
    }

    func markBackendUnreachable(message: String) {
        apiReachable = false
        asrReady = false
        llmReady = false
        backendStatusMessage = message
        asrStatusMessage = "Unavailable"
        llmStatusMessage = "Unavailable"
        llmProvider = "none"
        llmModel = nil
        llmPreset = nil
        lastHealthCheckAt = .now
    }

    func resetRemoteStatus() {
        apiReachable = false
        asrReady = false
        llmReady = false
        lastHealthCheckAt = nil
        llmProvider = "none"
        llmModel = nil
        llmPreset = nil

        if hasConfiguredBackendURL {
            backendStatusMessage = "Connection not checked"
            asrStatusMessage = "Check the server first"
            llmStatusMessage = "Check the server first"
        } else {
            backendStatusMessage = "Backend not configured"
            asrStatusMessage = "Add a server first"
            llmStatusMessage = "Add a server first"
        }
    }

    static let simulatorLoopbackBaseURLString = "http://127.0.0.1:3000"

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WorkspaceBootstrapState: String {
    case idle
    case loading
    case success
    case failed
}
