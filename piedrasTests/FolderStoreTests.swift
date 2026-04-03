import Foundation
import Testing
@testable import piedras

private final class FolderStoreMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            Self.requests.append(request)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        requests = []
    }
}

@MainActor
@Suite(.serialized)
struct FolderStoreTests {
    @Test
    func loadFoldersPromotesDefaultCollectionAndLocalizesDisplayName() async throws {
        FolderStoreMockURLProtocol.reset()
        defer { FolderStoreMockURLProtocol.reset() }

        let suiteName = "piedras.tests.folders.load.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FolderStoreMockURLProtocol.self]
        let apiClient = APIClient(
            settingsStore: settingsStore,
            authTokenStore: UserDefaultsAuthTokenStore(defaults: defaults),
            session: URLSession(configuration: configuration)
        )
        let store = FolderStore(apiClient: apiClient, settingsStore: settingsStore)

        FolderStoreMockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            #expect(request.url?.path == "/api/collections")
            let payload = """
            [
              { "id": "collection-notes", "name": "Notes", "isDefault": true },
              { "id": "collection-projects", "name": "项目资料", "isDefault": false }
            ]
            """
            return (response, Data(payload.utf8))
        }

        await store.loadFolders()

        #expect(store.folders.count == 2)
        #expect(store.folders.map(\.displayName) == ["笔记", "项目资料"])
        #expect(store.folders.first?.isDefault == true)
        #expect(settingsStore.defaultCollectionID == "collection-notes")
        #expect(settingsStore.selectedCollectionID == "collection-notes")
        #expect(settingsStore.activeCollectionID == "collection-notes")
    }

    @Test
    func createFolderAppendsRemoteCollectionAndSelectsIt() async throws {
        FolderStoreMockURLProtocol.reset()
        defer { FolderStoreMockURLProtocol.reset() }

        let suiteName = "piedras.tests.folders.create.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FolderStoreMockURLProtocol.self]
        let apiClient = APIClient(
            settingsStore: settingsStore,
            authTokenStore: UserDefaultsAuthTokenStore(defaults: defaults),
            session: URLSession(configuration: configuration)
        )
        let store = FolderStore(apiClient: apiClient, settingsStore: settingsStore)
        var requestIndex = 0

        FolderStoreMockURLProtocol.requestHandler = { request in
            requestIndex += 1
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            if requestIndex == 1 {
                #expect(request.httpMethod == "GET")
                let payload = """
                [
                  { "id": "collection-notes", "name": "Notes", "isDefault": true }
                ]
                """
                return (response, Data(payload.utf8))
            }

            #expect(request.httpMethod == "POST")
            let requestData = try #require(request.httpBody ?? data(from: request.httpBodyStream))
            let body = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: String])
            #expect(body["name"] == "项目归档")

            let payload = """
            { "id": "collection-archive", "name": "项目归档", "isDefault": false }
            """
            return (response, Data(payload.utf8))
        }

        await store.loadFolders()
        store.draftFolderName = "项目归档"

        let created = await store.createFolder()

        #expect(created == true)
        #expect(store.folders.map(\.displayName) == ["笔记", "项目归档"])
        #expect(settingsStore.selectedCollectionID == "collection-archive")
        #expect(settingsStore.activeCollectionID == "collection-archive")
        #expect(store.draftFolderName.isEmpty)
    }

    private func data(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }

        return data
    }
}
