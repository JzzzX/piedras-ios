import Foundation
import Observation

enum BackendConnectionState {
    case configuredUnchecked
    case reachable
    case unreachable
}

enum CapabilityStatusKind {
    case standby
    case checking
    case ready
    case unavailable
    case offline
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
        static let hiddenWorkspaceID = "piedras.settings.hiddenWorkspaceID"
#if DEBUG
        static let debugBackendBaseURLString = "piedras.settings.debugBackendBaseURLString"
#endif
    }

    private let defaults: UserDefaults

#if DEBUG
    var debugBackendBaseURLString: String {
        didSet {
            defaults.set(debugBackendBaseURLString, forKey: Key.debugBackendBaseURLString)

            guard normalized(debugBackendBaseURLString) != normalized(oldValue) else {
                return
            }

            hiddenWorkspaceID = nil
            workspaceBootstrapState = .idle
            workspaceStatusMessage = "等待连接云端"
            resetRemoteStatus()
        }
    }
#endif

    var hiddenWorkspaceID: String? {
        didSet {
            defaults.set(hiddenWorkspaceID, forKey: Key.hiddenWorkspaceID)
        }
    }

    var apiReachable = false
    var asrReady = false
    var llmReady = false
    var asrReachable = false
    var llmReachable = false
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

    init(defaults: UserDefaults = .standard, debugDefaultBackendBaseURLString: String? = nil) {
        self.defaults = defaults
        hiddenWorkspaceID = defaults.string(forKey: Key.hiddenWorkspaceID)
#if DEBUG
        debugBackendBaseURLString = defaults.string(forKey: Key.debugBackendBaseURLString)
            ?? debugDefaultBackendBaseURLString
            ?? ""
#endif
        workspaceStatusMessage = "等待连接云端"
        resetRemoteStatus()
    }

    var backendBaseURL: URL? {
        #if DEBUG
        let override = normalized(debugBackendBaseURLString)
        if !override.isEmpty, let url = URL(string: override) {
            return url
        }
        #endif

        return AppEnvironment.productionBackendBaseURL
    }

    var backendDisplayURLString: String {
        backendBaseURL?.absoluteString ?? AppEnvironment.productionBackendBaseURLString
    }

    var hasConfiguredBackendURL: Bool {
        backendBaseURL != nil
    }

    var requiresInitialBackendSetup: Bool {
        false
    }

    var backendConnectionState: BackendConnectionState {
        if apiReachable {
            return .reachable
        }

        if lastHealthCheckAt == nil {
            return .configuredUnchecked
        }

        return .unreachable
    }

    func blockingMessage(for capability: RemoteCapabilityKind) -> String? {
        if lastHealthCheckAt != nil, !apiReachable {
            return backendStatusMessage.isEmpty ? "\(AppEnvironment.cloudName) 暂时不可用。" : backendStatusMessage
        }

        switch capability {
        case .ai:
            if lastHealthCheckAt != nil, !llmReady {
                return llmStatusMessage
            }
        case .asr:
            if lastHealthCheckAt != nil, !asrReady {
                return asrStatusMessage
            }
        case .backend, .sync:
            break
        }

        return nil
    }

    func markBackendReachable(
        message: String = "\(AppEnvironment.cloudName) 在线",
        checkedAt: Date? = .now
    ) {
        apiReachable = true
        backendStatusMessage = message
        lastHealthCheckAt = checkedAt ?? .now
    }

    func markBackendUnreachable(message: String) {
        apiReachable = false
        asrReady = false
        llmReady = false
        asrReachable = false
        llmReachable = false
        backendStatusMessage = message
        asrStatusMessage = "服务不可用"
        llmStatusMessage = "服务不可用"
        llmProvider = "none"
        llmModel = nil
        llmPreset = nil
        lastHealthCheckAt = .now
    }

    func updateASRStatus(_ status: RemoteASRStatus) {
        asrReady = status.ready
        asrReachable = status.reachable ?? status.ready
        asrStatusMessage = status.message
        if let checkedAt = status.checkedAt {
            lastHealthCheckAt = checkedAt
        }
    }

    func updateLLMStatus(_ status: RemoteLLMStatus) {
        llmReady = status.ready
        llmReachable = status.reachable ?? status.ready
        llmStatusMessage = status.message
        llmProvider = status.provider
        llmModel = status.model
        llmPreset = status.preset
        if let checkedAt = status.checkedAt {
            lastHealthCheckAt = checkedAt
        }
    }

    func markLLMRequestSucceeded(provider: String? = nil) {
        apiReachable = true
        llmReady = true
        llmReachable = true
        llmStatusMessage = "AI 服务可用"
        lastHealthCheckAt = .now
        if let provider, !provider.isEmpty {
            llmProvider = provider
        }
    }

    func markLLMRequestFailed(message: String) {
        llmReady = false
        llmReachable = false
        llmStatusMessage = message
        lastHealthCheckAt = .now
    }

    func markASRStreamSucceeded() {
        apiReachable = true
        asrReady = true
        asrReachable = true
        asrStatusMessage = "实时转写已连接"
        lastHealthCheckAt = .now
    }

    func markASRStreamFailed(message: String) {
        asrReady = false
        asrReachable = false
        asrStatusMessage = message
        lastHealthCheckAt = .now
    }

    func resetRemoteStatus() {
        apiReachable = false
        asrReady = false
        llmReady = false
        asrReachable = false
        llmReachable = false
        lastHealthCheckAt = nil
        llmProvider = "none"
        llmModel = nil
        llmPreset = nil
        backendStatusMessage = "等待检查"
        asrStatusMessage = "等待检查"
        llmStatusMessage = "等待检查"
    }

    var backendCapabilityStatus: CapabilityStatusKind {
        if isCheckingHealth {
            return .checking
        }

        switch backendConnectionState {
        case .configuredUnchecked:
            return .standby
        case .reachable:
            return .ready
        case .unreachable:
            return .offline
        }
    }

    var asrCapabilityStatus: CapabilityStatusKind {
        if isCheckingHealth {
            return .checking
        }

        switch backendConnectionState {
        case .configuredUnchecked:
            return .standby
        case .unreachable:
            return .offline
        case .reachable:
            return asrReady ? .ready : .unavailable
        }
    }

    var llmCapabilityStatus: CapabilityStatusKind {
        if isCheckingHealth {
            return .checking
        }

        switch backendConnectionState {
        case .configuredUnchecked:
            return .standby
        case .unreachable:
            return .offline
        case .reachable:
            return llmReady ? .ready : .unavailable
        }
    }

    var backendHostLabel: String {
        backendBaseURL?.host ?? AppEnvironment.cloudName
    }

    var serviceModeLabel: String {
        #if DEBUG
        return isUsingDebugBackendOverride ? "Debug" : "Cloud"
        #else
        return "Cloud"
        #endif
    }

    #if DEBUG
    var isUsingDebugBackendOverride: Bool {
        !normalized(debugBackendBaseURLString).isEmpty
    }

    func clearDebugBackendOverride() {
        debugBackendBaseURLString = ""
    }
    #else
    var isUsingDebugBackendOverride: Bool {
        false
    }
    #endif

    func markBackendUnconfigured() {
        resetRemoteStatus()
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
