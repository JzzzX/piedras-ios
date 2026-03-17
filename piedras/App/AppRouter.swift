import Foundation
import Observation

enum AppRoute: Hashable {
    case meeting(String)
    case settings
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func showMeeting(id: String) {
        path.append(.meeting(id))
    }

    func showSettings() {
        path.append(.settings)
    }

    func popToRoot() {
        path.removeAll()
    }
}
