import Foundation
import SwiftData

@MainActor
final class AppContainer {
    private static let isXCTestRuntime = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let modelContainer: ModelContainer
    let router: AppRouter
    let settingsStore: SettingsStore
    let recordingSessionStore: RecordingSessionStore
    let appActivityCoordinator: AppActivityCoordinator
    let audioSessionCoordinator: AudioSessionCoordinator
    let audioRecorderService: AudioRecorderService
    let audioFileTranscriptionService: AudioFileTranscriptionService
    let meetingRepository: MeetingRepository
    let apiClient: APIClient
    let asrService: ASRService
    let workspaceBootstrapService: WorkspaceBootstrapService
    let meetingSyncService: MeetingSyncService
    let meetingStore: MeetingStore
    let globalChatStore: GlobalChatStore

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
        recordingSessionStore = RecordingSessionStore()
        appActivityCoordinator = AppActivityCoordinator()
        audioSessionCoordinator = AudioSessionCoordinator()
        audioRecorderService = AudioRecorderService(sessionCoordinator: audioSessionCoordinator)
        meetingRepository = MeetingRepository(modelContext: modelContainer.mainContext)
        apiClient = APIClient(settingsStore: settingsStore)
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
        meetingStore = MeetingStore(
            repository: meetingRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: appActivityCoordinator,
            audioRecorderService: audioRecorderService,
            audioFileTranscriptionService: audioFileTranscriptionService,
            apiClient: apiClient,
            asrService: asrService,
            workspaceBootstrapService: workspaceBootstrapService,
            meetingSyncService: meetingSyncService
        )
        globalChatStore = GlobalChatStore(
            apiClient: apiClient,
            settingsStore: settingsStore,
            workspaceBootstrapService: workspaceBootstrapService
        )

        AppStrings.syncLanguage(settingsStore.appLanguage)

        if inMemory {
            meetingRepository.seedPreviewDataIfNeeded(
                workspaceID: settingsStore.hiddenWorkspaceID,
                preferLocalOnly: true
            )
            meetingStore.loadMeetings()
        }
    }

    static var preview: AppContainer {
        AppContainer(inMemory: true)
    }
}
