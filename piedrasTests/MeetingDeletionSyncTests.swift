import Foundation
import Testing
@testable import piedras

private final class MockURLProtocol: URLProtocol {
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

@Suite(.serialized)
struct MeetingDeletionSyncTests {
    @MainActor
    @Test
    func fetchMeetingsExcludesDeletedTombstonesByDefault() throws {
        let repository = try makeRepository()
        repository.insert(
            Meeting(
                id: "visible-meeting",
                title: "Visible",
                syncState: .synced
            )
        )
        repository.insert(
            Meeting(
                id: "deleted-meeting",
                title: "Deleted",
                syncState: .deleted
            )
        )
        try repository.save()

        let visibleMeetings = try repository.fetchMeetings()
        let allMeetings = try repository.fetchMeetings(includeDeleted: true)

        #expect(visibleMeetings.map(\.id) == ["visible-meeting"])
        #expect(Set(allMeetings.map(\.id)) == Set(["visible-meeting", "deleted-meeting"]))
    }

    @MainActor
    @Test
    func deleteMeetingUsesLocalFirstTombstoneWithoutUserVisibleError() throws {
        let appContainer = try makeAppContainer()
        let repository = appContainer.meetingRepository
        try resetRepository(repository)

        let meeting = Meeting(
            id: "meeting-local-delete",
            title: "Delete locally first",
            audioRemotePath: "/audio/meeting-local-delete.m4a",
            hiddenWorkspaceId: "workspace-1",
            syncState: .synced,
            lastSyncedAt: .now
        )
        repository.insert(meeting)
        try repository.save()

        let meetingStore = appContainer.meetingStore
        meetingStore.clearLastError()
        meetingStore.loadMeetings()

        meetingStore.deleteMeeting(id: meeting.id)

        #expect(try repository.meeting(withID: meeting.id)?.syncState == .deleted)
        #expect(try repository.fetchMeetings().isEmpty)
        #expect(try repository.fetchMeetings(includeDeleted: true).map(\.id) == [meeting.id])
        #expect(meetingStore.meetings.isEmpty)
        #expect(meetingStore.lastErrorMessage == nil)
    }

    @MainActor
    @Test
    func syncPendingMeetingsPurgesDeletedTombstoneAfterRemoteDeleteSucceeds() async throws {
        let repository = try makeRepository()
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = MeetingSyncService(
            repository: repository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let meeting = Meeting(
            id: "meeting-delete-success",
            title: "To delete",
            syncState: .deleted,
            lastSyncedAt: .now
        )
        repository.insert(meeting)
        try repository.save()

        MockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, Data(#"{"success":true}"#.utf8))
        }
        defer { MockURLProtocol.reset() }

        let result = await syncService.syncPendingMeetings()

        #expect(result.syncedCount == 1)
        #expect(result.failedCount == 0)
        #expect(try repository.meeting(withID: meeting.id) == nil)
        #expect(MockURLProtocol.requests.count == 1)
        #expect(MockURLProtocol.requests.first?.httpMethod == "DELETE")
        #expect(MockURLProtocol.requests.first?.url?.path == "/api/meetings/\(meeting.id)")
    }

    @MainActor
    @Test
    func refreshRemoteMeetingsDoesNotResurrectDeletedTombstone() async throws {
        let repository = try makeRepository()
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = MeetingSyncService(
            repository: repository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let meeting = Meeting(
            id: "meeting-delete-pending",
            title: "Pending delete",
            hiddenWorkspaceId: "workspace-1",
            syncState: .deleted,
            lastSyncedAt: .now
        )
        repository.insert(meeting)
        try repository.save()
        var didRequestUnexpectedMeetingDetail = false

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            if url.path == "/api/meetings" {
                return (response, Data(#"[{"id":"meeting-delete-pending"}]"#.utf8))
            }

            didRequestUnexpectedMeetingDetail = true
            return (response, Data(#"{}"#.utf8))
        }
        defer { MockURLProtocol.reset() }

        let refreshedCount = try await syncService.refreshRemoteMeetings()

        #expect(refreshedCount == 1)
        #expect(try repository.meeting(withID: meeting.id)?.syncState == .deleted)
        #expect(didRequestUnexpectedMeetingDetail == false)
        #expect(MockURLProtocol.requests.count == 1)
        #expect(MockURLProtocol.requests.first?.url?.path == "/api/meetings")
    }

    @MainActor
    private func makeAppContainer() throws -> AppContainer {
        try #require(AppContainer.currentXCTestInstance)
    }

    @MainActor
    private func makeRepository() throws -> MeetingRepository {
        let repository = try makeAppContainer().meetingRepository
        try resetRepository(repository)
        return repository
    }

    @MainActor
    private func resetRepository(_ repository: MeetingRepository) throws {
        let meetings = try repository.fetchMeetings(includeDeleted: true)
        for meeting in meetings {
            try repository.delete(meeting)
        }
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        settingsStore.hiddenWorkspaceID = "workspace-1"
        return settingsStore
    }

    @MainActor
    private func makeAPIClient(settingsStore: SettingsStore) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )
    }
}
