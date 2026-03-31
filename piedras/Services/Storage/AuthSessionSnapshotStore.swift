import Foundation

struct CachedAuthSessionSnapshot: Codable, Equatable {
    let user: RemoteAuthUser
    let workspace: RemoteWorkspace
    let expiresAt: Date
    let savedAt: Date
}

@MainActor
protocol AuthSessionSnapshotStoring: AnyObject {
    var snapshot: CachedAuthSessionSnapshot? { get set }

    func clearSnapshot()
}

extension AuthSessionSnapshotStoring {
    func clearSnapshot() {
        snapshot = nil
    }
}

@MainActor
final class UserDefaultsAuthSessionSnapshotStore: AuthSessionSnapshotStoring {
    private enum Key {
        static let snapshot = "piedras.auth.sessionSnapshot"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var snapshot: CachedAuthSessionSnapshot? {
        get {
            guard let data = defaults.data(forKey: Key.snapshot) else {
                return nil
            }

            return try? decoder.decode(CachedAuthSessionSnapshot.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.snapshot)
                return
            }

            guard let data = try? encoder.encode(newValue) else {
                defaults.removeObject(forKey: Key.snapshot)
                return
            }

            defaults.set(data, forKey: Key.snapshot)
        }
    }
}

@MainActor
final class DiscardingAuthSessionSnapshotStore: AuthSessionSnapshotStoring {
    var snapshot: CachedAuthSessionSnapshot?
}
