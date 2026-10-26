import Foundation
import Testing
@testable import piedras

@MainActor
struct KeychainAuthTokenStoreTests {
    @Test
    func keychainStorePersistsAndClearsTokens() {
        let serviceName = "piedras.tests.auth.keychain.\(UUID().uuidString)"
        let firstStore = KeychainAuthTokenStore(service: serviceName, account: "session")
        let secondStore = KeychainAuthTokenStore(service: serviceName, account: "session")

        firstStore.clearTokens()
        firstStore.sessionToken = "secure-session-token"
        firstStore.refreshToken = "secure-refresh-token"

        #expect(secondStore.sessionToken == "secure-session-token")
        #expect(secondStore.refreshToken == "secure-refresh-token")

        secondStore.clearTokens()

        #expect(firstStore.sessionToken == nil)
        #expect(firstStore.refreshToken == nil)
    }
}
