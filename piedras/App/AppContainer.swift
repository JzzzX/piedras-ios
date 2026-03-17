import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let router: AppRouter
    let settingsStore: SettingsStore
    let recordingSessionStore: RecordingSessionStore
    let appActivityCoordinator: AppActivityCoordinator
    let audioSessionCoordinator: AudioSessionCoordinator
    let audioRecorderService: AudioRecorderService
    let meetingRepository: MeetingRepository
    let apiClient: APIClient
    let asrService: ASRService
    let workspaceBootstrapService: WorkspaceBootstrapService
    let meetingSyncService: MeetingSyncService
    let meetingStore: MeetingStore
    let globalChatStore: GlobalChatStore

    init(inMemory: Bool = false) {
        do {
            modelContainer = try ModelContainerFactory.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }

        router = AppRouter()
        settingsStore = SettingsStore()
        recordingSessionStore = RecordingSessionStore()
        appActivityCoordinator = AppActivityCoordinator()
        audioSessionCoordinator = AudioSessionCoordinator()
        audioRecorderService = AudioRecorderService(sessionCoordinator: audioSessionCoordinator)
        meetingRepository = MeetingRepository(modelContext: modelContainer.mainContext)
        apiClient = APIClient(settingsStore: settingsStore)
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
