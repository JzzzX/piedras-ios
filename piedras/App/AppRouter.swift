import Foundation
import Observation

enum AppRoute: Hashable {
    case meeting(String)
}

enum AppSheet: Identifiable, Equatable {
    case globalChat(initialQuestion: String?)
    case search
    case settings

    var id: String {
        switch self {
        case let .globalChat(initialQuestion):
            return "globalChat:\(initialQuestion ?? "")"
        case .search:
            return "search"
        case .settings:
            return "settings"
        }
    }
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

    func showGlobalChat(initialQuestion: String? = nil) {
        sheet = .globalChat(initialQuestion: initialQuestion)
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
