import SwiftData
import SwiftUI

@main
struct PiedrasApp: App {
    @State private var appContainer = AppContainer(
        inMemory: ProcessInfo.processInfo.arguments.contains("UITEST_IN_MEMORY")
    )

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(appContainer.modelContainer)
                .environment(appContainer.router)
                .environment(appContainer.settingsStore)
                .environment(appContainer.recordingSessionStore)
                .environment(appContainer.meetingStore)
                .environment(appContainer.globalChatStore)
        }
    }
}
