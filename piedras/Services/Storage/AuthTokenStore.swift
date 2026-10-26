import Foundation
import Security

@MainActor
protocol AuthTokenStoring: AnyObject {
    var sessionToken: String? { get set }
    var refreshToken: String? { get set }

    func clearTokens()
}

extension AuthTokenStoring {
    func clearSessionToken() {
        clearTokens()
    }
}

@MainActor
final class UserDefaultsAuthTokenStore: AuthTokenStoring {
    private enum Key {
        static let sessionToken = "piedras.auth.sessionToken"
        static let refreshToken = "piedras.auth.refreshToken"
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

    var refreshToken: String? {
        get {
            defaults.string(forKey: Key.refreshToken)
        }
        set {
            let normalized = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized, !normalized.isEmpty {
                defaults.set(normalized, forKey: Key.refreshToken)
            } else {
                defaults.removeObject(forKey: Key.refreshToken)
            }
        }
    }

    func clearTokens() {
        sessionToken = nil
        refreshToken = nil
    }
}

@MainActor
final class KeychainAuthTokenStore: AuthTokenStoring {
    private let service: String
    private let sessionTokenAccount: String
    private let refreshTokenAccount: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.mediocre.piedras",
        account: String = "auth.sessionToken",
        refreshTokenAccount: String = "auth.refreshToken"
    ) {
        self.service = service
        self.sessionTokenAccount = account
        self.refreshTokenAccount = refreshTokenAccount
    }

    var sessionToken: String? {
        get {
            readValue(account: sessionTokenAccount)
        }
        set {
            writeValue(newValue, account: sessionTokenAccount)
        }
    }

    var refreshToken: String? {
        get {
            readValue(account: refreshTokenAccount)
        }
        set {
            writeValue(newValue, account: refreshTokenAccount)
        }
    }

    func clearTokens() {
        SecItemDelete(baseQuery(account: sessionTokenAccount) as CFDictionary)
        SecItemDelete(baseQuery(account: refreshTokenAccount) as CFDictionary)
    }

    private func readValue(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeValue(_ value: String?, account: String) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalized, !normalized.isEmpty else {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            return
        }

        let encoded = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: encoded] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            return
        }

        var createQuery = baseQuery(account: account)
        createQuery[kSecValueData as String] = encoded
        createQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(createQuery as CFDictionary, nil)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
