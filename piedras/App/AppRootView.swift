import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            MeetingListView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .meeting(id):
                        MeetingDetailView(meetingID: id)
                    case .settings:
                        SettingsView()
                    }
                }
                .task {
                    meetingStore.loadIfNeeded()
                    meetingStore.handleScenePhaseChange(scenePhase)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            meetingStore.handleScenePhaseChange(newPhase)
        }
    }
}
