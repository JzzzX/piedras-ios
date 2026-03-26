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
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
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
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
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
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
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
    @Test
    func syncMeetingUploadsEndedLocalAudioAndClearsLocalCopy() async throws {
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = MeetingSyncService(
            repository: repository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let audioURL = try makeTemporaryAudioFile(named: "meeting-upload-success.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = Meeting(
            id: "meeting-upload-success",
            title: "Upload audio",
            status: .ended,
            audioLocalPath: audioURL.path,
            audioMimeType: "audio/m4a",
            audioDuration: 12,
            audioUpdatedAt: .now,
            hiddenWorkspaceId: "workspace-1",
            syncState: .pending
        )
        repository.insert(meeting)
        try repository.save()

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

            switch url.path {
            case "/api/meetings":
                let payload: [String: Any] = [
                    "id": meeting.id,
                    "title": meeting.title,
                    "date": meeting.date.ISO8601Format(),
                    "status": meeting.status.rawValue,
                    "duration": meeting.durationSeconds,
                    "workspaceId": meeting.hiddenWorkspaceId ?? "workspace-1",
                    "userNotes": meeting.userNotesPlainText,
                    "enhancedNotes": meeting.enhancedNotes,
                    "createdAt": Int(Date().timeIntervalSince1970 * 1000),
                    "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
                    "segments": [],
                    "chatMessages": [],
                    "hasAudio": false,
                    "audioUrl": NSNull(),
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            case "/api/meetings/\(meeting.id)/audio":
                return (
                    response,
                    Data(
                        #"{"hasAudio":true,"audioMimeType":"audio/m4a","audioDuration":12,"audioUpdatedAt":"2026-03-24T04:00:00.000Z","audioUrl":"/api/meetings/meeting-upload-success/audio?t=123"}"#.utf8
                    )
                )

            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { MockURLProtocol.reset() }

        try await syncService.syncMeeting(id: meeting.id)

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.syncState == .synced)
        #expect(refreshedMeeting.audioLocalPath == nil)
        #expect(refreshedMeeting.audioRemotePath == "https://example.com/api/meetings/meeting-upload-success/audio?t=123")
        #expect(FileManager.default.fileExists(atPath: audioURL.path) == false)
        #expect(MockURLProtocol.requests.count == 2)
        #expect(MockURLProtocol.requests.map { $0.url?.path ?? "" } == ["/api/meetings", "/api/meetings/\(meeting.id)/audio"])
        #expect(MockURLProtocol.requests.last?.httpMethod == "POST")
        #expect(MockURLProtocol.requests.last?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
    }

    @MainActor
    @Test
    func syncMeetingFinalizesEndedAudioWithSpeakerDiarization() async throws {
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = MeetingSyncService(
            repository: repository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let audioURL = try makeTemporaryAudioFile(named: "meeting-upload-diarized.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = Meeting(
            id: "meeting-upload-diarized",
            title: "Interview",
            status: .ended,
            audioLocalPath: audioURL.path,
            audioMimeType: "audio/m4a",
            audioDuration: 24,
            audioUpdatedAt: .now,
            hiddenWorkspaceId: "workspace-1",
            syncState: .pending
        )
        meeting.speakerDiarizationState = .processing
        repository.insert(meeting)
        try repository.save()

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

            switch url.path {
            case "/api/meetings":
                let payload: [String: Any] = [
                    "id": meeting.id,
                    "title": meeting.title,
                    "date": meeting.date.ISO8601Format(),
                    "status": meeting.status.rawValue,
                    "duration": meeting.durationSeconds,
                    "workspaceId": meeting.hiddenWorkspaceId ?? "workspace-1",
                    "speakers": [:],
                    "userNotes": meeting.userNotesPlainText,
                    "enhancedNotes": meeting.enhancedNotes,
                    "createdAt": Int(Date().timeIntervalSince1970 * 1000),
                    "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
                    "segments": [],
                    "chatMessages": [],
                    "hasAudio": false,
                    "audioUrl": NSNull(),
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            case "/api/meetings/\(meeting.id)/audio":
                #expect(url.query?.contains("finalizeTranscript=true") == true)
                return (
                    response,
                    Data(
                        """
                        {
                          "id": "\(meeting.id)",
                          "title": "Interview",
                          "date": "2026-03-24T04:00:00.000Z",
                          "status": "ended",
                          "duration": 24,
                          "audioMimeType": "audio/m4a",
                          "audioDuration": 24,
                          "audioUpdatedAt": "2026-03-24T04:00:00.000Z",
                          "userNotes": "",
                          "enhancedNotes": "",
                          "createdAt": "2026-03-24T03:50:00.000Z",
                          "updatedAt": "2026-03-24T04:00:00.000Z",
                          "workspaceId": "workspace-1",
                          "speakers": {
                            "spk_1": "面试官",
                            "spk_2": "候选人"
                          },
                          "segments": [
                            {
                              "id": "segment-1",
                              "speaker": "spk_1",
                              "text": "请做个自我介绍。",
                              "startTime": 0,
                              "endTime": 1200,
                              "isFinal": true,
                              "order": 0
                            }
                          ],
                          "chatMessages": [],
                          "hasAudio": true,
                          "audioUrl": "/api/meetings/\(meeting.id)/audio?t=123"
                        }
                        """.utf8
                    )
                )

            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { MockURLProtocol.reset() }

        try await syncService.syncMeeting(id: meeting.id)

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.syncState == .synced)
        #expect(refreshedMeeting.speakerDiarizationState == .ready)
        #expect(refreshedMeeting.audioLocalPath == nil)
        #expect(refreshedMeeting.speakers == [
            "spk_1": "面试官",
            "spk_2": "候选人",
        ])
        #expect(refreshedMeeting.orderedSegments.map { $0.speaker } == ["spk_1"])
        #expect(refreshedMeeting.orderedSegments.map { $0.text } == ["请做个自我介绍。"])
        #expect(MockURLProtocol.requests.map { $0.url?.path ?? "" } == ["/api/meetings", "/api/meetings/\(meeting.id)/audio"])
    }

    @MainActor
    @Test
    func syncMeetingKeepsLocalAudioWhenUploadFails() async throws {
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = MeetingSyncService(
            repository: repository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let audioURL = try makeTemporaryAudioFile(named: "meeting-upload-failure.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = Meeting(
            id: "meeting-upload-failure",
            title: "Upload fails",
            status: .ended,
            audioLocalPath: audioURL.path,
            audioMimeType: "audio/m4a",
            audioDuration: 18,
            audioUpdatedAt: .now,
            hiddenWorkspaceId: "workspace-1",
            syncState: .pending
        )
        repository.insert(meeting)
        try repository.save()

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let statusCode = url.path == "/api/meetings/\(meeting.id)/audio" ? 500 : 200
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            switch url.path {
            case "/api/meetings":
                let payload: [String: Any] = [
                    "id": meeting.id,
                    "title": meeting.title,
                    "date": meeting.date.ISO8601Format(),
                    "status": meeting.status.rawValue,
                    "duration": meeting.durationSeconds,
                    "workspaceId": meeting.hiddenWorkspaceId ?? "workspace-1",
                    "userNotes": meeting.userNotesPlainText,
                    "enhancedNotes": meeting.enhancedNotes,
                    "createdAt": Int(Date().timeIntervalSince1970 * 1000),
                    "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
                    "segments": [],
                    "chatMessages": [],
                    "hasAudio": false,
                    "audioUrl": NSNull(),
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            case "/api/meetings/\(meeting.id)/audio":
                return (response, Data(#"{"error":"upload failed"}"#.utf8))

            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { MockURLProtocol.reset() }

        await #expect(throws: Error.self) {
            try await syncService.syncMeeting(id: meeting.id)
        }

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.syncState == .failed)
        #expect(refreshedMeeting.audioLocalPath == audioURL.path)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(MockURLProtocol.requests.map { $0.url?.path ?? "" } == ["/api/meetings", "/api/meetings/\(meeting.id)/audio"])
    }

    @MainActor
    @Test
    func failedFinalizeUploadRemainsRetryableOnNextSyncPass() async throws {
        let fixture = try makeRepositoryFixture()
        let repository = fixture.repository
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = MeetingSyncService(
            repository: repository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let audioURL = try makeTemporaryAudioFile(named: "meeting-finalize-retry.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = Meeting(
            id: "meeting-finalize-retry",
            title: "Finalize retry",
            status: .ended,
            audioLocalPath: audioURL.path,
            audioMimeType: "audio/m4a",
            audioDuration: 22,
            audioUpdatedAt: .now,
            hiddenWorkspaceId: "workspace-1",
            syncState: .pending
        )
        meeting.speakerDiarizationState = .processing
        repository.insert(meeting)
        try repository.save()

        var audioUploadAttempts = 0
        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let statusCode: Int
            if url.path == "/api/meetings/\(meeting.id)/audio" {
                audioUploadAttempts += 1
                statusCode = audioUploadAttempts == 1 ? 500 : 200
            } else {
                statusCode = 200
            }

            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            switch url.path {
            case "/api/meetings":
                let payload: [String: Any] = [
                    "id": meeting.id,
                    "title": meeting.title,
                    "date": meeting.date.ISO8601Format(),
                    "status": meeting.status.rawValue,
                    "duration": meeting.durationSeconds,
                    "workspaceId": meeting.hiddenWorkspaceId ?? "workspace-1",
                    "speakers": [:],
                    "userNotes": meeting.userNotesPlainText,
                    "enhancedNotes": meeting.enhancedNotes,
                    "createdAt": Int(Date().timeIntervalSince1970 * 1000),
                    "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
                    "segments": [],
                    "chatMessages": [],
                    "hasAudio": false,
                    "audioUrl": NSNull(),
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            case "/api/meetings/\(meeting.id)/audio":
                if audioUploadAttempts == 1 {
                    return (response, Data(#"{"error":"finalize failed"}"#.utf8))
                }

                return (
                    response,
                    Data(
                        """
                        {
                          "id": "\(meeting.id)",
                          "title": "Finalize retry",
                          "date": "2026-03-24T04:00:00.000Z",
                          "status": "ended",
                          "duration": 22,
                          "audioMimeType": "audio/m4a",
                          "audioDuration": 22,
                          "audioUpdatedAt": "2026-03-24T04:00:00.000Z",
                          "userNotes": "",
                          "enhancedNotes": "",
                          "createdAt": "2026-03-24T03:50:00.000Z",
                          "updatedAt": "2026-03-24T04:00:00.000Z",
                          "workspaceId": "workspace-1",
                          "speakers": {
                            "spk_1": "说话人 1"
                          },
                          "segments": [
                            {
                              "id": "segment-1",
                              "speaker": "spk_1",
                              "text": "补转写成功",
                              "startTime": 0,
                              "endTime": 1200,
                              "isFinal": true,
                              "order": 0
                            }
                          ],
                          "chatMessages": [],
                          "hasAudio": true,
                          "audioUrl": "/api/meetings/\(meeting.id)/audio?t=123"
                        }
                        """.utf8
                    )
                )

            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { MockURLProtocol.reset() }

        await #expect(throws: Error.self) {
            try await syncService.syncMeeting(id: meeting.id)
        }

        let failedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(failedMeeting.syncState == .failed)
        #expect(failedMeeting.speakerDiarizationState == .processing)
        #expect(failedMeeting.audioLocalPath == audioURL.path)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))

        let batchResult = await syncService.syncPendingMeetings()

        let recoveredMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(batchResult.syncedCount == 1)
        #expect(batchResult.failedCount == 0)
        #expect(recoveredMeeting.syncState == .synced)
        #expect(recoveredMeeting.speakerDiarizationState == .ready)
        #expect(recoveredMeeting.audioLocalPath == nil)
        #expect(recoveredMeeting.orderedSegments.map(\.text) == ["补转写成功"])
    }

    @MainActor
    private func makeAppContainer() throws -> AppContainer {
        if let container = AppContainer.currentXCTestInstance {
            return container
        }

        return AppContainer(inMemory: true)
    }

    @MainActor
    private func makeRepositoryFixture() throws -> (appContainer: AppContainer, repository: MeetingRepository) {
        let appContainer = try makeAppContainer()
        let repository = appContainer.meetingRepository
        try resetRepository(repository)
        return (appContainer, repository)
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

    private func makeTemporaryAudioFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: url)
        return url
    }
}
