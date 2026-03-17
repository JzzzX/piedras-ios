import Foundation
import Observation

enum AppRoute: Hashable {
    case meeting(String)
}

enum AppSheet: String, Identifiable {
    case globalChat
    case search
    case settings

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var sheet: AppSheet?

    func showMeeting(id: String) {
        path.append(.meeting(id))
    }

    func showSettings() {
        sheet = .settings
    }

    func showGlobalChat() {
        sheet = .globalChat
    }

    func showSearch() {
        sheet = .search
    }

    func dismissSheet() {
        sheet = nil
    }

    func popToRoot() {
        path.removeAll()
    }
}
