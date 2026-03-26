import Foundation

@MainActor
protocol AuthTokenStoring: AnyObject {
    var sessionToken: String? { get set }

    func clearSessionToken()
}

@MainActor
final class UserDefaultsAuthTokenStore: AuthTokenStoring {
    private enum Key {
        static let sessionToken = "piedras.auth.sessionToken"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var sessionToken: String? {
        get {
            defaults.string(forKey: Key.sessionToken)
        }
        set {
            let normalized = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized, !normalized.isEmpty {
                defaults.set(normalized, forKey: Key.sessionToken)
            } else {
                defaults.removeObject(forKey: Key.sessionToken)
            }
        }
    }

    func clearSessionToken() {
        sessionToken = nil
    }
}
