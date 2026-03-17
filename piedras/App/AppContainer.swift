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
        meetingStore = MeetingStore(
            repository: meetingRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            audioRecorderService: audioRecorderService
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
