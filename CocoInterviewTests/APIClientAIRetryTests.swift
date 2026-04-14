import Foundation
import Testing
@testable import CocoInterview

private final class AIRetryMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

private final class AIStreamingRetryMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest, URLProtocolClient, URLProtocol) throws -> Void)?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler, let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            Self.requests.append(request)
            try handler(request, client, self)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        requests = []
    }
}

@Suite(.serialized)
struct APIClientAIRetryTests {
    @MainActor
    @Test
    func enhanceNotesRetriesTimedOutRequestOnce() async throws {
        AIRetryMockURLProtocol.reset()
        defer { AIRetryMockURLProtocol.reset() }

        let settingsStore = makeSettingsStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIRetryMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )

        var attempts = 0
        AIRetryMockURLProtocol.requestHandler = { request in
            attempts += 1
            if attempts == 1 {
                throw URLError(.timedOut)
            }

            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json",
                        "X-Request-Id": "rid-enhance-2",
                    ]
                )
            )
            let payload = """
            {
              "content": "结构化纪要",
              "provider": "aihubmix"
            }
            """
            return (response, Data(payload.utf8))
        }

        let result = try await client.enhanceNotes(
            EnhanceRequestPayload(
                transcript: "会议内容",
                userNotes: "用户笔记",
                meetingTitle: "周会",
                segmentCommentsContext: "",
                noteAttachmentsContext: "",
                promptOptions: nil
            )
        )

        #expect(result.content == "结构化纪要")
        #expect(result.provider == "aihubmix")
        #expect(attempts == 2)
        #expect(AIRetryMockURLProtocol.requests.count == 2)
        #expect(
            AIRetryMockURLProtocol.requests.allSatisfy {
                ($0.value(forHTTPHeaderField: "X-Request-Id")?.isEmpty == false)
            }
        )
    }

    @MainActor
    @Test
    func streamChatRetriesTimeoutBeforeFirstChunk() async throws {
        AIStreamingRetryMockURLProtocol.reset()
        defer { AIStreamingRetryMockURLProtocol.reset() }

        let settingsStore = makeSettingsStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStreamingRetryMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )

        var attempts = 0
        AIStreamingRetryMockURLProtocol.requestHandler = { request, client, protocolInstance in
            attempts += 1
            if attempts == 1 {
                throw URLError(.timedOut)
            }

            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "text/plain; charset=utf-8",
                        "X-Request-Id": "rid-chat-2",
                    ]
                )
            )
            client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(protocolInstance, didLoad: Data("重试成功".utf8))
            client.urlProtocolDidFinishLoading(protocolInstance)
        }

        let stream = try await client.streamChat(
            ChatRequestPayload(
                transcript: "会议转写",
                userNotes: "",
                enhancedNotes: "",
                noteAttachmentsContext: "",
                segmentCommentsContext: "",
                chatHistory: [],
                question: "帮我总结"
            )
        )

        var result = ""
        for try await partial in stream {
            result = partial
        }

        #expect(result == "重试成功")
        #expect(attempts == 2)
        #expect(AIStreamingRetryMockURLProtocol.requests.count == 2)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "cocointerview.tests.ai-retry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
    }
}
