import Foundation
import Observation
import SwiftData
import Testing
@testable import piedras

private final class ChatMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StreamingChatMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest, URLProtocolClient, URLProtocol) throws -> Void)?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler, let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            try handler(request, client, self)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ObservationInvalidationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Suite(.serialized)
struct ChatSessionFlowTests {
    @MainActor
    @Test
    func globalChatDraftDoesNotPersistUntilFirstSend() async throws {
        ChatMockURLProtocol.reset()
        defer { ChatMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let repository = ChatSessionRepository(modelContext: container.mainContext)
        let store = GlobalChatStore(
            apiClient: apiClient,
            settingsStore: settingsStore,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            chatSessionRepository: repository
        )

        store.startNewDraft()
        #expect(try repository.fetchSessions(scope: .global).isEmpty)
        #expect(store.messages.isEmpty)

        ChatMockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain; charset=utf-8"]
                )
            )
            return (response, Data("这是总结结果。".utf8))
        }

        let sent = await store.sendMessage("总结一下最近的会议")

        #expect(sent)
        #expect(try repository.fetchSessions(scope: .global).count == 1)
        #expect(store.messages.map(\.role) == ["user", "assistant"])
        #expect(store.sessions.first?.title == "总结一下最近的会议")
    }

    @MainActor
    @Test
    func globalChatPayloadIncludesLocalCommentContextPrioritizingKeywordMatches() async throws {
        ChatMockURLProtocol.reset()
        defer { ChatMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let repository = ChatSessionRepository(modelContext: container.mainContext)
        let store = GlobalChatStore(
            apiClient: apiClient,
            settingsStore: settingsStore,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            chatSessionRepository: repository,
            meetingRepository: meetingRepository
        )

        let matchingMeeting = Meeting(
            title: "灰度上线会",
            date: Date(timeIntervalSince1970: 1_710_000_000),
            hiddenWorkspaceId: "workspace-1",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120)
        )
        let matchingSegment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们下周先灰度上线。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let matchingAnnotation = SegmentAnnotation(comment: "这里的灰度范围只覆盖 iOS 内测用户。")
        matchingAnnotation.segment = matchingSegment
        matchingSegment.annotation = matchingAnnotation
        matchingSegment.meeting = matchingMeeting
        matchingMeeting.segments = [matchingSegment]
        meetingRepository.insert(matchingMeeting)

        let recentMeeting = Meeting(
            title: "近期同步",
            date: Date(timeIntervalSince1970: 1_710_000_200),
            hiddenWorkspaceId: "workspace-1",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_300)
        )
        let recentSegment = TranscriptSegment(
            speaker: "Speaker B",
            text: "这周先整理埋点。",
            startTime: 25_000,
            endTime: 31_000,
            orderIndex: 0
        )
        let recentAnnotation = SegmentAnnotation(comment: "这里主要是埋点整理，不涉及发布节奏。")
        recentAnnotation.segment = recentSegment
        recentSegment.annotation = recentAnnotation
        recentSegment.meeting = recentMeeting
        recentMeeting.segments = [recentSegment]
        meetingRepository.insert(recentMeeting)
        try meetingRepository.save()

        var capturedLocalCommentContext = ""

        ChatMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain; charset=utf-8"]
                )
            )

            let body = try requestBodyData(from: request)
            let raw = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            capturedLocalCommentContext = raw["localCommentContext"] as? String ?? ""

            return (response, Data("这里是首页回答。".utf8))
        }

        let sent = await store.sendMessage("帮我总结灰度上线安排")

        #expect(sent)
        #expect(capturedLocalCommentContext.contains("--- 本地补充评论上下文 ---"))
        #expect(capturedLocalCommentContext.contains("会议：灰度上线会"))
        #expect(capturedLocalCommentContext.contains("[00:12] 原句：我们下周先灰度上线。"))
        #expect(capturedLocalCommentContext.contains("评论：这里的灰度范围只覆盖 iOS 内测用户。"))
        #expect(capturedLocalCommentContext.firstRange(of: "会议：灰度上线会")?.lowerBound ?? capturedLocalCommentContext.startIndex
            < capturedLocalCommentContext.firstRange(of: "会议：近期同步")?.lowerBound ?? capturedLocalCommentContext.endIndex)
    }

    @MainActor
    @Test
    func globalChatPayloadIncludesLocalRetrievalContextBuiltFromTranscriptNotesAndComments() async throws {
        ChatMockURLProtocol.reset()
        defer { ChatMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let repository = ChatSessionRepository(modelContext: container.mainContext)
        let store = GlobalChatStore(
            apiClient: apiClient,
            settingsStore: settingsStore,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            chatSessionRepository: repository,
            meetingRepository: meetingRepository
        )

        let meeting = Meeting(
            title: "灰度上线会",
            date: Date(timeIntervalSince1970: 1_710_000_000),
            userNotesPlainText: "用户笔记里提到先面向内测用户。",
            enhancedNotes: "AI 笔记记录了灰度范围和行动项。",
            hiddenWorkspaceId: "workspace-1",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120)
        )
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们下周先灰度上线。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(comment: "这里的灰度范围只覆盖 iOS 内测用户。")
        annotation.segment = segment
        segment.annotation = annotation
        segment.meeting = meeting
        meeting.segments = [segment]
        meetingRepository.insert(meeting)
        try meetingRepository.save()

        var capturedLocalRetrievalContext = ""
        var capturedLocalRetrievalSourceCount = 0

        ChatMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain; charset=utf-8"]
                )
            )

            let body = try requestBodyData(from: request)
            let raw = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            capturedLocalRetrievalContext = raw["localRetrievalContext"] as? String ?? ""
            capturedLocalRetrievalSourceCount = (raw["localRetrievalSources"] as? [[String: Any]])?.count ?? 0

            return (response, Data("这里是首页回答。".utf8))
        }

        let sent = await store.sendMessage("帮我总结灰度上线安排")

        #expect(sent)
        #expect(capturedLocalRetrievalContext.contains("[S1] 会议：灰度上线会"))
        #expect(capturedLocalRetrievalContext.contains("AI 笔记记录了灰度范围和行动项。"))
        #expect(capturedLocalRetrievalContext.contains("这里的灰度范围只覆盖 iOS 内测用户。"))
        #expect(capturedLocalRetrievalSourceCount == 1)
    }

    @MainActor
    @Test
    func globalChatPayloadIncludesAnnotationImageTextInLocalRetrievalContext() async throws {
        ChatMockURLProtocol.reset()
        defer { ChatMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let settingsStore = makeSettingsStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let repository = ChatSessionRepository(modelContext: container.mainContext)
        let store = GlobalChatStore(
            apiClient: apiClient,
            settingsStore: settingsStore,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            chatSessionRepository: repository,
            meetingRepository: meetingRepository
        )

        let meeting = Meeting(
            title: "发布时间确认会",
            date: Date(timeIntervalSince1970: 1_710_000_000),
            hiddenWorkspaceId: "workspace-1",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120)
        )
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们看一下图片里的发布时间。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(
            comment: "",
            imageTextContext: "路线图写着：4 月 8 日灰度，4 月 15 日全量。",
            imageTextStatus: .ready,
            imageTextUpdatedAt: .now
        )
        annotation.segment = segment
        segment.annotation = annotation
        segment.meeting = meeting
        meeting.segments = [segment]
        meetingRepository.insert(meeting)
        try meetingRepository.save()

        var capturedLocalRetrievalContext = ""

        ChatMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain; charset=utf-8"]
                )
            )

            let body = try requestBodyData(from: request)
            let raw = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            capturedLocalRetrievalContext = raw["localRetrievalContext"] as? String ?? ""

            return (response, Data("这里是首页回答。".utf8))
        }

        let sent = await store.sendMessage("帮我总结图片上的发布时间")

        #expect(sent)
        #expect(capturedLocalRetrievalContext.contains("路线图写着：4 月 8 日灰度，4 月 15 日全量。"))
    }

    @Test
    func meetingChatPayloadUsesOnlyActiveSessionHistory() {
        let firstSession = ChatSession(
            id: "session-1",
            scope: .meeting,
            title: "第一条",
            messages: [
                ChatMessage(role: "user", content: "旧问题", orderIndex: 0),
                ChatMessage(role: "assistant", content: "旧回答", orderIndex: 1),
            ]
        )
        let activeSession = ChatSession(
            id: "session-2",
            scope: .meeting,
            title: "当前问题",
            messages: [
                ChatMessage(role: "user", content: "当前问题", orderIndex: 0),
                ChatMessage(role: "assistant", content: "当前回答", orderIndex: 1),
            ]
        )
        let meeting = Meeting(
            title: "测试会议",
            enhancedNotes: "这里是 AI 笔记",
            chatSessions: [firstSession, activeSession]
        )

        let payload = MeetingPayloadMapper.makeChatPayload(
            from: meeting,
            session: activeSession,
            question: "继续追问"
        )

        #expect(payload.chatHistory.map(\.content) == ["当前问题", "当前回答"])
        #expect(payload.question == "继续追问")
    }

    @MainActor
    @Test
    func deletingActiveMeetingSessionFallsBackToLatestRemainingSession() throws {
        let appContainer = AppContainer(inMemory: true)
        let repository = appContainer.chatSessionRepository
        let store = appContainer.meetingStore
        let meeting = try #require(store.createMeeting())

        let earlierSession = repository.makeDraftSession(scope: .meeting, meeting: meeting)
        repository.appendUserMessage("先前的问题", to: earlierSession)
        earlierSession.createdAt = Date(timeIntervalSince1970: 100)
        earlierSession.updatedAt = Date(timeIntervalSince1970: 110)

        let latestSession = repository.makeDraftSession(scope: .meeting, meeting: meeting)
        repository.appendUserMessage("当前的问题", to: latestSession)
        latestSession.createdAt = Date(timeIntervalSince1970: 200)
        latestSession.updatedAt = Date(timeIntervalSince1970: 210)

        try repository.save()

        store.prepareChatSessions(for: meeting.id)
        store.activateChatSession(latestSession.id, for: meeting.id)

        store.deleteChatSession(latestSession.id, for: meeting.id)

        #expect(store.activeChatSession(for: meeting.id)?.id == earlierSession.id)
        #expect(store.chatMessages(for: meeting.id).map(\.content) == ["先前的问题"])

        store.deleteChatSession(earlierSession.id, for: meeting.id)

        #expect(store.activeChatSession(for: meeting.id) == nil)
        #expect(store.chatMessages(for: meeting.id).isEmpty)
    }

    @MainActor
    @Test
    func readingMeetingChatSessionsDoesNotMutateSelectionState() throws {
        let appContainer = AppContainer(inMemory: true)
        let repository = appContainer.chatSessionRepository
        let store = appContainer.meetingStore
        let meeting = try #require(store.createMeeting())

        let session = repository.makeDraftSession(scope: .meeting, meeting: meeting)
        repository.appendUserMessage("帮我继续追问", to: session)
        try repository.save()

        #expect(store.activeChatSessionIDs.isEmpty)

        let sessions = store.chatSessions(for: meeting.id)

        #expect(sessions.map(\.id) == [session.id])
        #expect(store.activeChatSessionIDs.isEmpty)
    }

    @MainActor
    @Test
    func applyingRemoteMeetingDoesNotEraseExistingSessionMessages() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)

        let meeting = try meetingRepository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        let session = chatRepository.makeDraftSession(scope: .meeting, meeting: meeting)
        chatRepository.appendUserMessage("主要内容?", to: session)
        chatRepository.appendAssistantPlaceholder(to: session).content = "这里是回答"
        try chatRepository.save()

        let remote = RemoteMeetingDetail(
            id: meeting.id,
            title: meeting.title,
            date: meeting.date,
            status: meeting.status.rawValue,
            duration: meeting.durationSeconds,
            audioMimeType: nil,
            audioDuration: nil,
            audioUpdatedAt: nil,
            userNotes: meeting.userNotesPlainText,
            enhancedNotes: meeting.enhancedNotes,
            createdAt: meeting.createdAt,
            updatedAt: meeting.updatedAt,
            workspaceId: meeting.hiddenWorkspaceId,
            segments: [],
            chatMessages: [],
            hasAudio: false,
            audioUrl: nil
        )

        MeetingPayloadMapper.apply(
            remote: remote,
            to: meeting,
            repository: meetingRepository,
            baseURL: nil
        )

        #expect(session.orderedMessages.map(\.content) == ["主要内容?", "这里是回答"])
    }

    @MainActor
    @Test
    func applyingRemoteMeetingWithFlatChatMessagesPreservesSessionMessagesAfterReload() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)

        let meeting = try meetingRepository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        let session = chatRepository.makeDraftSession(scope: .meeting, meeting: meeting)
        let userMessage = chatRepository.appendUserMessage("主要内容?", to: session)
        let assistantMessage = chatRepository.appendAssistantPlaceholder(to: session)
        assistantMessage.content = "这里是回答"
        try chatRepository.save()

        let remote = RemoteMeetingDetail(
            id: meeting.id,
            title: meeting.title,
            date: meeting.date,
            status: meeting.status.rawValue,
            duration: meeting.durationSeconds,
            audioMimeType: nil,
            audioDuration: nil,
            audioUpdatedAt: nil,
            userNotes: meeting.userNotesPlainText,
            enhancedNotes: meeting.enhancedNotes,
            createdAt: meeting.createdAt,
            updatedAt: meeting.updatedAt,
            workspaceId: meeting.hiddenWorkspaceId,
            segments: [],
            chatMessages: [
                RemoteChatMessage(
                    id: userMessage.id,
                    role: userMessage.role,
                    content: userMessage.content,
                    timestamp: userMessage.timestamp
                ),
                RemoteChatMessage(
                    id: assistantMessage.id,
                    role: assistantMessage.role,
                    content: assistantMessage.content,
                    timestamp: assistantMessage.timestamp
                ),
            ],
            hasAudio: false,
            audioUrl: nil
        )

        MeetingPayloadMapper.apply(
            remote: remote,
            to: meeting,
            repository: meetingRepository,
            baseURL: nil
        )
        try meetingRepository.save()

        let reloadedMeeting = try #require(try meetingRepository.meeting(withID: meeting.id))
        let reloadedSession = try #require(reloadedMeeting.chatSessions.first(where: { $0.id == session.id }))

        #expect(reloadedSession.orderedMessages.map(\.content) == ["主要内容?", "这里是回答"])
    }

    @MainActor
    @Test
    func sendingMeetingChatKeepsMessagesVisibleAfterSync() async throws {
        ChatMockURLProtocol.reset()
        defer { ChatMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let settingsStore = makeSettingsStore()
        settingsStore.workspaceBootstrapState = .success
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let meetingSyncService = MeetingSyncService(
            repository: meetingRepository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let meetingStore = MeetingStore(
            repository: meetingRepository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: RecordingSessionStore(),
            appActivityCoordinator: AppActivityCoordinator(),
            audioRecorderService: AudioRecorderService(sessionCoordinator: AudioSessionCoordinator()),
            audioFileTranscriptionService: AudioFileTranscriptionService(apiClient: apiClient),
            apiClient: apiClient,
            asrService: ASRService(apiClient: apiClient),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: meetingSyncService
        )

        let meeting = try meetingRepository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "测试会议"
        try meetingRepository.save()

        let nowMillis = Int64(Date(timeIntervalSince1970: 1_710_000_000).timeIntervalSince1970 * 1000)
        var capturedUpsertChatContents: [String] = []

        ChatMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": contentType(for: url.path)]
                )
            )

            switch url.path {
            case "/healthz":
                let payload: [String: Any] = [
                    "ok": true,
                    "database": true,
                    "checkedAt": nowMillis,
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            case "/api/chat":
                return (response, Data("这里是回答".utf8))

            case "/api/meetings":
                let body = try requestBodyData(from: request)
                let raw = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let chatMessages = try #require(raw["chatMessages"] as? [[String: Any]])
                capturedUpsertChatContents = chatMessages.compactMap { $0["content"] as? String }

                let payload: [String: Any] = [
                    "id": raw["id"] as? String ?? meeting.id,
                    "title": raw["title"] as? String ?? meeting.title,
                    "date": raw["date"] as? String ?? nowMillis,
                    "status": raw["status"] as? String ?? meeting.status.rawValue,
                    "duration": raw["duration"] as? Int ?? meeting.durationSeconds,
                    "workspaceId": raw["workspaceId"] as? String ?? "workspace-1",
                    "userNotes": raw["userNotes"] as? String ?? "",
                    "enhancedNotes": raw["enhancedNotes"] as? String ?? "",
                    "createdAt": nowMillis,
                    "updatedAt": nowMillis,
                    "segments": [],
                    "chatMessages": chatMessages,
                    "hasAudio": false,
                    "audioUrl": NSNull(),
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            default:
                throw URLError(.unsupportedURL)
            }
        }

        let didSend = await meetingStore.sendChatMessage(question: "主要内容?", for: meeting.id)

        #expect(didSend)
        #expect(capturedUpsertChatContents == ["主要内容?", "这里是回答"])
        #expect(meetingStore.chatSessions(for: meeting.id).count == 1)
        #expect(meetingStore.activeChatSession(for: meeting.id)?.title == "主要内容?")
        #expect(meetingStore.chatMessages(for: meeting.id).map(\.content) == ["主要内容?", "这里是回答"])
    }

    @MainActor
    @Test
    func streamingMeetingChatEmitsUpdatesWhileAssistantReplyArrives() async throws {
        StreamingChatMockURLProtocol.reset()
        defer { StreamingChatMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let settingsStore = makeSettingsStore()
        settingsStore.workspaceBootstrapState = .success
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingChatMockURLProtocol.self]
        let apiClient = APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )
        let meetingRepository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let meetingSyncService = MeetingSyncService(
            repository: meetingRepository,
            settingsStore: settingsStore,
            apiClient: apiClient
        )
        let meetingStore = MeetingStore(
            repository: meetingRepository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: RecordingSessionStore(),
            appActivityCoordinator: AppActivityCoordinator(),
            audioRecorderService: AudioRecorderService(sessionCoordinator: AudioSessionCoordinator()),
            audioFileTranscriptionService: AudioFileTranscriptionService(apiClient: apiClient),
            apiClient: apiClient,
            asrService: ASRService(apiClient: apiClient),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: meetingSyncService
        )

        let meeting = try meetingRepository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "测试会议"
        try meetingRepository.save()

        let counter = ObservationInvalidationCounter()
        var observedMessageSnapshots: [[String]] = []
        func trackMessages() {
            let currentSnapshot = meetingStore.chatMessages(for: meeting.id).map(\.content)
            if observedMessageSnapshots.last != currentSnapshot {
                observedMessageSnapshots.append(currentSnapshot)
            }
            withObservationTracking {
                _ = meetingStore.chatMessages(for: meeting.id).map(\.content)
            } onChange: {
                counter.increment()
                Task { @MainActor in
                    trackMessages()
                }
            }
        }
        trackMessages()

        StreamingChatMockURLProtocol.requestHandler = { request, client, protocolInstance in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": contentType(for: url.path)]
                )
            )

            switch url.path {
            case "/healthz":
                let payload: [String: Any] = [
                    "ok": true,
                    "database": true,
                    "checkedAt": Int(Date().timeIntervalSince1970 * 1000),
                ]
                client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(protocolInstance, didLoad: try JSONSerialization.data(withJSONObject: payload))
                client.urlProtocolDidFinishLoading(protocolInstance)

            case "/api/chat":
                client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    client.urlProtocol(protocolInstance, didLoad: Data("这是".utf8))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    client.urlProtocol(protocolInstance, didLoad: Data("来自测试".utf8))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    client.urlProtocol(protocolInstance, didLoad: Data("后端的回答。".utf8))
                    client.urlProtocolDidFinishLoading(protocolInstance)
                }

            case "/api/meetings":
                let body = try requestBodyData(from: request)
                let raw = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let chatMessages = try #require(raw["chatMessages"] as? [[String: Any]])
                let payload: [String: Any] = [
                    "id": raw["id"] as? String ?? meeting.id,
                    "title": raw["title"] as? String ?? meeting.title,
                    "date": raw["date"] as? String ?? meeting.date.ISO8601Format(),
                    "status": raw["status"] as? String ?? meeting.status.rawValue,
                    "duration": raw["duration"] as? Int ?? meeting.durationSeconds,
                    "workspaceId": raw["workspaceId"] as? String ?? "workspace-1",
                    "userNotes": raw["userNotes"] as? String ?? "",
                    "enhancedNotes": raw["enhancedNotes"] as? String ?? "",
                    "createdAt": Int(Date().timeIntervalSince1970 * 1000),
                    "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
                    "segments": [],
                    "chatMessages": chatMessages,
                    "hasAudio": false,
                    "audioUrl": NSNull(),
                ]
                client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(protocolInstance, didLoad: try JSONSerialization.data(withJSONObject: payload))
                client.urlProtocolDidFinishLoading(protocolInstance)

            default:
                throw URLError(.unsupportedURL)
            }
        }

        let sendTask = Task {
            await meetingStore.sendChatMessage(question: "帮我总结", for: meeting.id)
        }

        let didSend = await sendTask.value

        #expect(didSend)
        #expect(counter.value >= 2)
        #expect(
            observedMessageSnapshots.contains { snapshot in
                snapshot.count == 2
                    && snapshot[0] == "帮我总结"
                    && !snapshot[1].isEmpty
                    && snapshot[1] != "这是来自测试后端的回答。"
            }
        )
        #expect(meetingStore.chatMessages(for: meeting.id).map(\.content) == ["帮我总结", "这是来自测试后端的回答。"])
    }

    @MainActor
    @Test
    func observingMeetingChatMessagesDoesNotReactToSessionMessageMutation() throws {
        let appContainer = AppContainer(inMemory: true)
        let repository = appContainer.chatSessionRepository
        let store = appContainer.meetingStore
        let meeting = try #require(store.createMeeting())

        let session = repository.makeDraftSession(scope: .meeting, meeting: meeting)
        try repository.save()

        store.prepareChatSessions(for: meeting.id)
        store.activateChatSession(session.id, for: meeting.id)

        var invalidationCount = 0
        withObservationTracking {
            _ = store.chatMessages(for: meeting.id).map(\.content)
        } onChange: {
            invalidationCount += 1
        }

        _ = repository.appendUserMessage("这是一条新消息", to: session)

        #expect(invalidationCount == 1)
    }

    @MainActor
    @Test
    func observingMeetingChatMessagesReactsToAssistantContentMutation() throws {
        let appContainer = AppContainer(inMemory: true)
        let repository = appContainer.chatSessionRepository
        let store = appContainer.meetingStore
        let meeting = try #require(store.createMeeting())

        let session = repository.makeDraftSession(scope: .meeting, meeting: meeting)
        _ = repository.appendUserMessage("帮我总结", to: session)
        let assistantMessage = repository.appendAssistantPlaceholder(to: session)
        try repository.save()

        store.prepareChatSessions(for: meeting.id)
        store.activateChatSession(session.id, for: meeting.id)

        var invalidationCount = 0
        withObservationTracking {
            _ = store.chatMessages(for: meeting.id).map(\.content)
        } onChange: {
            invalidationCount += 1
        }

        assistantMessage.content = "这里是新的回答"

        #expect(invalidationCount == 1)
        #expect(store.chatMessages(for: meeting.id).map(\.content) == ["帮我总结", "这里是新的回答"])
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.chat.\(UUID().uuidString)"
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
        configuration.protocolClasses = [ChatMockURLProtocol.self]
        return APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )
    }

    private func contentType(for path: String) -> String {
        switch path {
        case "/api/chat":
            "text/plain; charset=utf-8"
        default:
            "application/json"
        }
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw URLError(.badServerResponse)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)

            if bytesRead < 0 {
                throw stream.streamError ?? URLError(.cannotParseResponse)
            }

            if bytesRead == 0 {
                break
            }

            data.append(contentsOf: buffer.prefix(bytesRead))
        }

        return data
    }
}
