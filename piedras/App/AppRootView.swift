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
                    }
                }
                .task {
                    meetingStore.loadIfNeeded()
                    meetingStore.handleScenePhaseChange(scenePhase)
                }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case let .globalChat(initialQuestion):
                GlobalChatView(initialQuestion: initialQuestion)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .search:
                MeetingSearchView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .settings:
                NavigationStack {
                    SettingsView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            meetingStore.handleScenePhaseChange(newPhase)
        }
    }
}
