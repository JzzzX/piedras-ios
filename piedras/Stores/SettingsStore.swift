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

enum SyncIssueKind: String, Codable {
    case backendOffline
    case workspaceBootstrapFailed
    case syncFailed
    case refreshFailed
}

@MainActor
@Observable
final class SettingsStore {
    private struct RemoteStatusSnapshot: Codable {
        let apiReachable: Bool
        let asrReady: Bool
        let llmReady: Bool
        let asrReachable: Bool
        let llmReachable: Bool
        let lastHealthCheckAt: Date?
        let backendStatusMessage: String
        let asrStatusMessage: String
        let llmStatusMessage: String
        let llmProvider: String
        let llmModel: String?
        let llmPreset: String?
    }

    private struct SyncStatusSnapshot: Codable {
        let summaryMessage: String
        let detailMessage: String
        let issueKind: SyncIssueKind?
        let lastFailureAt: Date?
        let retryCount: Int
        let nextRetryAt: Date?
        let lastSuccessfulSyncAt: Date?
        let isAutoRecovering: Bool
    }

    private enum Key {
        static let hiddenWorkspaceID = "piedras.settings.hiddenWorkspaceID"
        static let defaultCollectionID = "piedras.settings.defaultCollectionID"
        static let recentlyDeletedCollectionID = "piedras.settings.recentlyDeletedCollectionID"
        static let selectedCollectionID = "piedras.settings.selectedCollectionID"
        static let appLanguage = "piedras.settings.appLanguage"
        static let remoteStatusSnapshot = "piedras.settings.remoteStatusSnapshot"
        static let syncStatusSnapshot = "piedras.settings.syncStatusSnapshot"
#if DEBUG
        static let debugBackendBaseURLString = "piedras.settings.debugBackendBaseURLString"
#endif
    }

    private enum Constants {
        static let restoredStatusMaxAge: TimeInterval = 6 * 60 * 60
        static let restoredSyncStatusMaxAge: TimeInterval = 7 * 24 * 60 * 60
    }

    private let defaults: UserDefaults

    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
            AppStrings.syncLanguage(appLanguage)
        }
    }

#if DEBUG
    var debugBackendBaseURLString: String {
        didSet {
            defaults.set(debugBackendBaseURLString, forKey: Key.debugBackendBaseURLString)

            guard normalized(debugBackendBaseURLString) != normalized(oldValue) else {
                return
            }

            hiddenWorkspaceID = nil
            defaultCollectionID = nil
            recentlyDeletedCollectionID = nil
            selectedCollectionID = nil
            workspaceBootstrapState = .idle
            workspaceStatusMessage = "等待连接云端"
            resetRemoteStatus()
            clearRemoteStatusSnapshot()
        }
    }
#endif

    var hiddenWorkspaceID: String? {
        didSet {
            defaults.set(hiddenWorkspaceID, forKey: Key.hiddenWorkspaceID)
        }
    }

    var defaultCollectionID: String? {
        didSet {
            defaults.set(defaultCollectionID, forKey: Key.defaultCollectionID)
        }
    }

    var recentlyDeletedCollectionID: String? {
        didSet {
            defaults.set(recentlyDeletedCollectionID, forKey: Key.recentlyDeletedCollectionID)
        }
    }

    var selectedCollectionID: String? {
        didSet {
            defaults.set(selectedCollectionID, forKey: Key.selectedCollectionID)
        }
    }

    var activeCollectionID: String? {
        selectedCollectionID ?? defaultCollectionID
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
    var syncDetailMessage = ""
    var syncIssueKind: SyncIssueKind?
    var syncLastFailureAt: Date?
    var syncRetryCount = 0
    var syncNextRetryAt: Date?
    var lastSuccessfulSyncAt: Date?
    var isAutoRecoveringSync = false
    var isCheckingHealth = false
    var isSyncing = false

    init(defaults: UserDefaults = .standard, debugDefaultBackendBaseURLString: String? = nil) {
        self.defaults = defaults
        self.appLanguage = defaults.string(forKey: Key.appLanguage)
            .flatMap { AppLanguage(rawValue: $0) } ?? .chinese
        hiddenWorkspaceID = defaults.string(forKey: Key.hiddenWorkspaceID)
        defaultCollectionID = defaults.string(forKey: Key.defaultCollectionID)
        recentlyDeletedCollectionID = defaults.string(forKey: Key.recentlyDeletedCollectionID)
        selectedCollectionID = defaults.string(forKey: Key.selectedCollectionID)
            ?? defaults.string(forKey: Key.defaultCollectionID)
#if DEBUG
        debugBackendBaseURLString = defaults.string(forKey: Key.debugBackendBaseURLString)
            ?? debugDefaultBackendBaseURLString
            ?? ""
#endif
        workspaceStatusMessage = "等待连接云端"
        resetRemoteStatus()
        restoreRemoteStatusSnapshotIfAvailable()
        restoreSyncStatusSnapshotIfAvailable()
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
            return nil
        case .asr:
            if lastHealthCheckAt != nil,
               !asrReady,
               asrStatusMessage != "等待检查",
               asrStatusMessage != "未检查" {
                return asrStatusMessage
            }
        case .backend, .sync:
            break
        }

        return nil
    }

    func warningMessage(for capability: RemoteCapabilityKind) -> String? {
        switch capability {
        case .ai:
            guard apiReachable,
                  lastHealthCheckAt != nil,
                  !llmReady else {
                return nil
            }

            return llmStatusMessage
        case .backend, .asr, .sync:
            return nil
        }
    }

    func markBackendReachable(
        message: String = "\(AppEnvironment.cloudName) 在线",
        checkedAt: Date? = .now
    ) {
        apiReachable = true
        backendStatusMessage = message
        lastHealthCheckAt = checkedAt ?? .now
        persistRemoteStatusSnapshot()
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
        persistRemoteStatusSnapshot()
    }

    func updateASRStatus(_ status: RemoteASRStatus) {
        asrReady = status.ready
        asrReachable = status.reachable ?? status.ready
        asrStatusMessage = status.message
        if let checkedAt = status.checkedAt {
            lastHealthCheckAt = checkedAt
        }
        persistRemoteStatusSnapshot()
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
        persistRemoteStatusSnapshot()
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
        persistRemoteStatusSnapshot()
    }

    func markLLMRequestFailed(message: String) {
        llmReady = false
        llmReachable = false
        llmStatusMessage = message
        lastHealthCheckAt = .now
        persistRemoteStatusSnapshot()
    }

    func markASRStreamSucceeded() {
        apiReachable = true
        asrReady = true
        asrReachable = true
        asrStatusMessage = "实时转写已连接"
        lastHealthCheckAt = .now
        persistRemoteStatusSnapshot()
    }

    func markASRStreamFailed(message: String) {
        asrReady = false
        asrReachable = false
        asrStatusMessage = message
        lastHealthCheckAt = .now
        persistRemoteStatusSnapshot()
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

    func applyDebugBackendOverride(_ value: String) {
        debugBackendBaseURLString = normalized(value)
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
        clearRemoteStatusSnapshot()
        clearSyncStatus()
    }

    static let simulatorLoopbackBaseURLString = "http://127.0.0.1:3000"

    var requiresSyncRecoveryAttention: Bool {
        syncIssueKind != nil || isAutoRecoveringSync || syncRetryCount > 0
    }

    func markSyncRecovering(
        summary: String = "正在自动恢复同步…",
        retryCount: Int,
        nextRetryAt: Date?
    ) {
        syncStatusMessage = summary
        syncRetryCount = retryCount
        syncNextRetryAt = nextRetryAt
        isAutoRecoveringSync = true
        persistSyncStatusSnapshot()
    }

    func markSyncIssue(
        kind: SyncIssueKind,
        detail: String,
        summary: String,
        retryCount: Int,
        nextRetryAt: Date?,
        failureAt: Date = .now,
        isAutoRecovering: Bool
    ) {
        syncStatusMessage = summary
        syncDetailMessage = detail
        syncIssueKind = kind
        syncLastFailureAt = failureAt
        syncRetryCount = retryCount
        syncNextRetryAt = nextRetryAt
        isAutoRecoveringSync = isAutoRecovering
        persistSyncStatusSnapshot()
    }

    func markSyncSuccess(summary: String, syncedAt: Date = .now) {
        syncStatusMessage = summary
        syncDetailMessage = ""
        syncIssueKind = nil
        syncLastFailureAt = nil
        syncRetryCount = 0
        syncNextRetryAt = nil
        lastSuccessfulSyncAt = syncedAt
        isAutoRecoveringSync = false
        persistSyncStatusSnapshot()
    }

    func clearSyncStatus() {
        syncStatusMessage = ""
        syncDetailMessage = ""
        syncIssueKind = nil
        syncLastFailureAt = nil
        syncRetryCount = 0
        syncNextRetryAt = nil
        lastSuccessfulSyncAt = nil
        isAutoRecoveringSync = false
        clearSyncStatusSnapshot()
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreRemoteStatusSnapshotIfAvailable() {
        guard let data = defaults.data(forKey: Key.remoteStatusSnapshot),
              let snapshot = try? JSONDecoder().decode(RemoteStatusSnapshot.self, from: data),
              let checkedAt = snapshot.lastHealthCheckAt,
              Date().timeIntervalSince(checkedAt) <= Constants.restoredStatusMaxAge,
              snapshot.apiReachable || snapshot.asrReady || snapshot.llmReady else {
            return
        }

        apiReachable = snapshot.apiReachable
        asrReady = snapshot.asrReady
        llmReady = snapshot.llmReady
        asrReachable = snapshot.asrReachable
        llmReachable = snapshot.llmReachable
        lastHealthCheckAt = snapshot.lastHealthCheckAt
        backendStatusMessage = snapshot.backendStatusMessage
        asrStatusMessage = snapshot.asrStatusMessage
        llmStatusMessage = snapshot.llmStatusMessage
        llmProvider = snapshot.llmProvider
        llmModel = snapshot.llmModel
        llmPreset = snapshot.llmPreset
    }

    private func persistRemoteStatusSnapshot() {
        let snapshot = RemoteStatusSnapshot(
            apiReachable: apiReachable,
            asrReady: asrReady,
            llmReady: llmReady,
            asrReachable: asrReachable,
            llmReachable: llmReachable,
            lastHealthCheckAt: lastHealthCheckAt,
            backendStatusMessage: backendStatusMessage,
            asrStatusMessage: asrStatusMessage,
            llmStatusMessage: llmStatusMessage,
            llmProvider: llmProvider,
            llmModel: llmModel,
            llmPreset: llmPreset
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: Key.remoteStatusSnapshot)
    }

    private func restoreSyncStatusSnapshotIfAvailable() {
        guard let data = defaults.data(forKey: Key.syncStatusSnapshot),
              let snapshot = try? JSONDecoder().decode(SyncStatusSnapshot.self, from: data) else {
            return
        }

        let referenceDate = snapshot.lastFailureAt ?? snapshot.lastSuccessfulSyncAt
        if let referenceDate,
           Date().timeIntervalSince(referenceDate) > Constants.restoredSyncStatusMaxAge {
            clearSyncStatusSnapshot()
            return
        }

        syncStatusMessage = snapshot.summaryMessage
        syncDetailMessage = snapshot.detailMessage
        syncIssueKind = snapshot.issueKind
        syncLastFailureAt = snapshot.lastFailureAt
        syncRetryCount = snapshot.retryCount
        syncNextRetryAt = snapshot.nextRetryAt
        lastSuccessfulSyncAt = snapshot.lastSuccessfulSyncAt
        isAutoRecoveringSync = snapshot.isAutoRecovering
    }

    private func persistSyncStatusSnapshot() {
        let snapshot = SyncStatusSnapshot(
            summaryMessage: syncStatusMessage,
            detailMessage: syncDetailMessage,
            issueKind: syncIssueKind,
            lastFailureAt: syncLastFailureAt,
            retryCount: syncRetryCount,
            nextRetryAt: syncNextRetryAt,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            isAutoRecovering: isAutoRecoveringSync
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: Key.syncStatusSnapshot)
    }

    private func clearRemoteStatusSnapshot() {
        defaults.removeObject(forKey: Key.remoteStatusSnapshot)
    }

    private func clearSyncStatusSnapshot() {
        defaults.removeObject(forKey: Key.syncStatusSnapshot)
    }
}

enum WorkspaceBootstrapState: String {
    case idle
    case loading
    case success
    case failed
}
