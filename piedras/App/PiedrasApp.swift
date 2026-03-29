import SwiftData
import SwiftUI

@main
struct PiedrasApp: App {
    private static let isXCTestRuntime = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    @State private var appContainer = AppContainer(
        inMemory: Self.isXCTestRuntime || ProcessInfo.processInfo.arguments.contains("UITEST_IN_MEMORY")
    )

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(appContainer.modelContainer)
                .environment(appContainer.router)
                .environment(appContainer.authStore)
                .environment(appContainer.settingsStore)
                .environment(appContainer.recordingSessionStore)
                .environment(appContainer.meetingStore)
                .environment(appContainer.globalChatStore)
                .environment(appContainer.annotationStore)
                .onOpenURL { url in
                    Task {
                        _ = await appContainer.authStore.handleAuthCallback(url: url)
                    }
                }
        }
    }
}
