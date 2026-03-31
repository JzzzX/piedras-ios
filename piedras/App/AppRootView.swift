import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        Group {
            if isResolvingSession {
                sessionLoadingView
            } else if authStore.isAuthenticated {
                authenticatedContent
            } else {
                AuthView()
            }
        }
        .task {
            guard !authStore.hasResolvedInitialSession else { return }
            await authStore.bootstrapSession()
        }
        .onChange(of: authStore.phase, initial: true) { _, newPhase in
            guard newPhase == .authenticated else { return }
            handleAuthenticatedAppearance()
        }
        .onChange(of: authStore.isSessionValidated, initial: true) { _, isValidated in
            guard authStore.isAuthenticated, isValidated else { return }
            handleAuthenticatedAppearance()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard authStore.isAuthenticated, authStore.isSessionValidated else { return }
            meetingStore.handleScenePhaseChange(newPhase)
        }
        .onChange(of: settingsStore.requiresInitialBackendSetup, initial: true) { _, requiresSetup in
            guard authStore.isAuthenticated, authStore.isSessionValidated, requiresSetup else { return }
            presentSettingsIfNeeded()
        }
    }

    private var authenticatedContent: some View {
        @Bindable var router = router

        return NavigationStack(path: $router.path) {
            MeetingListView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .meeting(id):
                        MeetingDetailView(meetingID: id)
                    }
                }
                .task {
                    handleAuthenticatedAppearance()
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
                .interactiveDismissDisabled(settingsStore.requiresInitialBackendSetup)
            }
        }
    }

    private var sessionLoadingView: some View {
        ZStack {
            AppGlassBackdrop()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppTheme.ink)

                Text(AppStrings.current.authRestoringSession)
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .softCard()
        }
    }

    private func presentSettingsIfNeeded() {
        guard settingsStore.requiresInitialBackendSetup else { return }
        router.showSettings()
    }

    private var isResolvingSession: Bool {
        !authStore.hasResolvedInitialSession
    }

    private func handleAuthenticatedAppearance() {
        if authStore.isSessionValidated {
            meetingStore.loadIfNeeded()
            meetingStore.handleScenePhaseChange(scenePhase)
            presentSettingsIfNeeded()
        } else {
            meetingStore.loadMeetings()
        }
    }
}
