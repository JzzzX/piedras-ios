import Foundation
import SwiftData

@MainActor
final class AppContainer {
    private static let isXCTestRuntime = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private(set) static weak var currentInstance: AppContainer?
    private(set) static weak var currentXCTestInstance: AppContainer?

    let modelContainer: ModelContainer
    let router: AppRouter
    let settingsStore: SettingsStore
    let authTokenStore: any AuthTokenStoring
    let authSessionSnapshotStore: any AuthSessionSnapshotStoring
    let authStore: AuthStore
    let recordingSessionStore: RecordingSessionStore
    let appActivityCoordinator: AppActivityCoordinator
    let recordingLiveActivityCoordinator: RecordingLiveActivityCoordinator
    let audioSessionCoordinator: AudioSessionCoordinator
    let audioRecorderService: AudioRecorderService
    let audioFileTranscriptionService: AudioFileTranscriptionService
    let meetingRepository: MeetingRepository
    let chatSessionRepository: ChatSessionRepository
    let apiClient: APIClient
    let asrService: ASRService
    let workspaceBootstrapService: WorkspaceBootstrapService
    let meetingSyncService: MeetingSyncService
    let meetingStore: MeetingStore
    let globalChatStore: GlobalChatStore
    let annotationRepository: AnnotationRepository
    let annotationStore: AnnotationStore
    let annotationImageTextExtractor: any AnnotationImageTextExtracting

    init(inMemory: Bool = false) {
        let processArguments = ProcessInfo.processInfo.arguments
        let shouldUseIsolatedDefaults = inMemory || Self.isXCTestRuntime || processArguments.contains("UITEST_ISOLATED_DEFAULTS")
        let shouldDefaultToSimulatorBackend = inMemory || Self.isXCTestRuntime || processArguments.contains("UITEST_USE_SIMULATOR_BACKEND")
        let settingsDefaults: UserDefaults
        if shouldUseIsolatedDefaults,
           let ephemeralDefaults = UserDefaults(suiteName: "piedras.ui-tests.in-memory") {
            ephemeralDefaults.removePersistentDomain(forName: "piedras.ui-tests.in-memory")
            settingsDefaults = ephemeralDefaults
        } else {
            settingsDefaults = .standard
        }

        do {
            modelContainer = try ModelContainerFactory.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }

        router = AppRouter()
        settingsStore = SettingsStore(
            defaults: settingsDefaults,
            debugDefaultBackendBaseURLString: shouldDefaultToSimulatorBackend ? SettingsStore.simulatorLoopbackBaseURLString : nil
        )
        if shouldUseIsolatedDefaults {
            authTokenStore = UserDefaultsAuthTokenStore(defaults: settingsDefaults)
        } else {
            authTokenStore = KeychainAuthTokenStore()
        }
        authSessionSnapshotStore = UserDefaultsAuthSessionSnapshotStore(defaults: settingsDefaults)
        recordingSessionStore = RecordingSessionStore()
        appActivityCoordinator = AppActivityCoordinator()
        recordingLiveActivityCoordinator = RecordingLiveActivityCoordinator()
        audioSessionCoordinator = AudioSessionCoordinator()
        audioRecorderService = AudioRecorderService(sessionCoordinator: audioSessionCoordinator)
        meetingRepository = MeetingRepository(modelContext: modelContainer.mainContext)
        chatSessionRepository = ChatSessionRepository(modelContext: modelContainer.mainContext)
        apiClient = APIClient(settingsStore: settingsStore, authTokenStore: authTokenStore)
        authStore = AuthStore(
            apiClient: apiClient,
            tokenStore: authTokenStore,
            snapshotStore: authSessionSnapshotStore
        )
        audioFileTranscriptionService = AudioFileTranscriptionService(apiClient: apiClient)
        asrService = ASRService(apiClient: apiClient)
        workspaceBootstrapService = WorkspaceBootstrapService(
            apiClient: apiClient,
            settingsStore: settingsStore
        )
        meetingSyncService = MeetingSyncService(
            repository: meetingRepository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        annotationImageTextExtractor = VisionAnnotationImageTextExtractor()
        meetingStore = MeetingStore(
            repository: meetingRepository,
            chatSessionRepository: chatSessionRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: appActivityCoordinator,
            recordingLiveActivityCoordinator: recordingLiveActivityCoordinator,
            audioRecorderService: audioRecorderService,
            audioFileTranscriptionService: audioFileTranscriptionService,
            apiClient: apiClient,
            asrService: asrService,
            workspaceBootstrapService: workspaceBootstrapService,
            meetingSyncService: meetingSyncService,
            noteAttachmentImageTextExtractor: annotationImageTextExtractor
        )
        globalChatStore = GlobalChatStore(
            apiClient: apiClient,
            settingsStore: settingsStore,
            workspaceBootstrapService: workspaceBootstrapService,
            chatSessionRepository: chatSessionRepository,
            meetingRepository: meetingRepository
        )
        annotationRepository = AnnotationRepository(modelContext: modelContainer.mainContext)
        annotationStore = AnnotationStore(
            repository: annotationRepository,
            imageTextExtractor: annotationImageTextExtractor
        )

        authStore.logoutBlockMessageProvider = { [weak meetingStore] in
            meetingStore?.logoutBlockingMessage()
        }
        authStore.didAuthenticate = { [weak settingsStore, weak globalChatStore, weak meetingStore] user, workspace in
            guard let settingsStore else { return }
            settingsStore.hiddenWorkspaceID = workspace.id
            settingsStore.workspaceBootstrapState = .success
            settingsStore.workspaceStatusMessage = "已连接 \(user.email)"
            settingsStore.clearSyncStatus()
            globalChatStore?.startNewDraft()
            meetingStore?.handleAuthenticationRecovered()
        }
        authStore.didUnauthenticate = { [weak router, weak meetingStore, weak globalChatStore] in
            meetingStore?.resetLocalAccountData()
            globalChatStore?.startNewDraft()
            router?.dismissSheet()
            router?.popToRoot()
        }

        if Self.isXCTestRuntime {
            Self.currentXCTestInstance = self
        }
        Self.currentInstance = self

        AppStrings.syncLanguage(settingsStore.appLanguage)

        if inMemory {
            authStore.phase = .authenticated
            authStore.hasResolvedInitialSession = true
            authStore.isSessionValidated = true
            authStore.currentUser = .init(id: "preview-user", email: "preview@piedras.local")
            authStore.currentWorkspace = .init(id: "preview-workspace", name: "Preview")
            meetingRepository.seedPreviewDataIfNeeded(
                workspaceID: settingsStore.hiddenWorkspaceID,
                preferLocalOnly: true
            )
            meetingStore.loadMeetings()
        } else if !Self.isXCTestRuntime {
            let storeForBackfill = annotationStore
            Task { @MainActor [weak storeForBackfill] in
                await storeForBackfill?.backfillImageTextIfNeeded()
            }
        }
    }

    static var preview: AppContainer {
        AppContainer(inMemory: true)
    }
}
