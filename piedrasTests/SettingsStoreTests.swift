import Foundation
import Testing
@testable import piedras

@MainActor
struct SettingsStoreTests {
    @Test
    func aiBlockingMessageDoesNotBlockWhenBackendIsReachable() {
        let suiteName = "piedras.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        store.markBackendReachable(message: "online")
        store.markLLMRequestFailed(message: "AI timeout")

        #expect(store.blockingMessage(for: .ai) == nil)
        #expect(store.warningMessage(for: .ai) == "AI timeout")
    }

    @Test
    func aiWarningMessageClearsAfterSuccessfulRequest() {
        let suiteName = "piedras.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        store.markBackendReachable(message: "online")
        store.markLLMRequestFailed(message: "AI timeout")
        store.markLLMRequestSucceeded(provider: "openai")

        #expect(store.warningMessage(for: .ai) == nil)
    }

    @Test
    func syncIssueSnapshotPersistsRetryDiagnostics() {
        let suiteName = "piedras.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let now = Date()
        let nextRetryAt = now.addingTimeInterval(120)
        let failureAt = now.addingTimeInterval(-30)
        let store = SettingsStore(defaults: defaults)

        store.markSyncIssue(
            kind: .syncFailed,
            detail: "request timeout",
            summary: "后台同步失败，将稍后自动重试。",
            retryCount: 2,
            nextRetryAt: nextRetryAt,
            failureAt: failureAt,
            isAutoRecovering: true
        )

        let restored = SettingsStore(defaults: defaults)

        #expect(restored.syncIssueKind == .syncFailed)
        #expect(restored.syncStatusMessage == "后台同步失败，将稍后自动重试。")
        #expect(restored.syncDetailMessage == "request timeout")
        #expect(restored.syncRetryCount == 2)
        #expect(restored.syncNextRetryAt == nextRetryAt)
        #expect(restored.syncLastFailureAt == failureAt)
        #expect(restored.isAutoRecoveringSync == true)
        #expect(restored.requiresSyncRecoveryAttention == true)
    }

    @Test
    func syncSuccessClearsRetryAttentionButKeepsLastSuccessfulTimestamp() {
        let suiteName = "piedras.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        let syncedAt = Date(timeIntervalSince1970: 3_000)

        store.markSyncIssue(
            kind: .backendOffline,
            detail: "offline",
            summary: "云端暂时不可用，将稍后自动重试。",
            retryCount: 1,
            nextRetryAt: Date(timeIntervalSince1970: 2_500),
            failureAt: Date(timeIntervalSince1970: 2_000),
            isAutoRecovering: true
        )
        store.markSyncSuccess(summary: "启动同步完成。", syncedAt: syncedAt)

        #expect(store.syncIssueKind == nil)
        #expect(store.syncRetryCount == 0)
        #expect(store.syncNextRetryAt == nil)
        #expect(store.syncLastFailureAt == nil)
        #expect(store.isAutoRecoveringSync == false)
        #expect(store.requiresSyncRecoveryAttention == false)
        #expect(store.lastSuccessfulSyncAt == syncedAt)
        #expect(store.syncStatusMessage == "启动同步完成。")
    }

    @Test
    func collectionSelectionPersistsAndFallsBackToDefaultCollection() {
        let suiteName = "piedras.tests.settings.collections.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        store.defaultCollectionID = "collection-notes"
        store.selectedCollectionID = "collection-projects"

        let restored = SettingsStore(defaults: defaults)

        #expect(restored.defaultCollectionID == "collection-notes")
        #expect(restored.selectedCollectionID == "collection-projects")
        #expect(restored.activeCollectionID == "collection-projects")

        restored.selectedCollectionID = nil

        #expect(restored.activeCollectionID == "collection-notes")
    }
}
