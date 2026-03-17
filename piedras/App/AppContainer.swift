import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let router: AppRouter
    let settingsStore: SettingsStore
    let recordingSessionStore: RecordingSessionStore
    let audioSessionCoordinator: AudioSessionCoordinator
    let audioRecorderService: AudioRecorderService
    let meetingRepository: MeetingRepository
    let apiClient: APIClient
    let workspaceBootstrapService: WorkspaceBootstrapService
    let meetingSyncService: MeetingSyncService
    let meetingStore: MeetingStore

    init(inMemory: Bool = false) {
        do {
            modelContainer = try ModelContainerFactory.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }

        router = AppRouter()
        settingsStore = SettingsStore()
        recordingSessionStore = RecordingSessionStore()
        audioSessionCoordinator = AudioSessionCoordinator()
        audioRecorderService = AudioRecorderService(sessionCoordinator: audioSessionCoordinator)
        meetingRepository = MeetingRepository(modelContext: modelContainer.mainContext)
        apiClient = APIClient(settingsStore: settingsStore)
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
            audioRecorderService: audioRecorderService,
            apiClient: apiClient,
            workspaceBootstrapService: workspaceBootstrapService,
            meetingSyncService: meetingSyncService
        )

        if inMemory {
            meetingRepository.seedPreviewDataIfNeeded(workspaceID: settingsStore.hiddenWorkspaceID)
            meetingStore.loadMeetings()
        }
    }

    static var preview: AppContainer {
        AppContainer(inMemory: true)
    }
}
