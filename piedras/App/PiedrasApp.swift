import SwiftData
import SwiftUI

@main
struct PiedrasApp: App {
    @State private var appContainer = AppContainer()

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
