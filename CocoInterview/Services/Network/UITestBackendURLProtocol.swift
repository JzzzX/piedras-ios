import Foundation

final class UITestBackendURLProtocol: URLProtocol {
    private static let stubbedReply = "这是来自测试后端的回答。"

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "127.0.0.1" || host == "localhost"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try makeResponse(for: url)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            switch url.path {
            case "/healthz":
                client.urlProtocol(self, didLoad: try makeHealthPayload())
            case "/api/chat", "/api/chat/global":
                client.urlProtocol(self, didLoad: Data(Self.stubbedReply.utf8))
            case "/api/meetings":
                client.urlProtocol(self, didLoad: try makeMeetingUpsertPayload(from: request))
            default:
                client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            client.urlProtocolDidFinishLoading(self)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }

    private func makeResponse(for url: URL) throws -> HTTPURLResponse {
        let headers = ["Content-Type": contentType(for: url.path)]
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    private func contentType(for path: String) -> String {
        switch path {
        case "/api/chat", "/api/chat/global":
            return "text/plain; charset=utf-8"
        default:
            return "application/json"
        }
    }

    private func makeHealthPayload() throws -> Data {
        let payload: [String: Any] = [
            "ok": true,
            "database": true,
            "checkedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func makeMeetingUpsertPayload(from request: URLRequest) throws -> Data {
        let body = try Self.requestBodyData(from: request)
        let raw = try (JSONSerialization.jsonObject(with: body) as? [String: Any]).unwrap()
        let chatMessages = raw["chatMessages"] as? [[String: Any]] ?? []
        let nowMillis = Int(Date().timeIntervalSince1970 * 1000)

        let payload: [String: Any] = [
            "id": raw["id"] as? String ?? UUID().uuidString,
            "title": raw["title"] as? String ?? "测试会议",
            "date": raw["date"] as? String ?? Date().ISO8601Format(),
            "status": raw["status"] as? String ?? "draft",
            "duration": raw["duration"] as? Int ?? 0,
            "workspaceId": raw["workspaceId"] as? String ?? "workspace-1",
            "collectionId": raw["collectionId"] ?? NSNull(),
            "previousCollectionId": raw["previousCollectionId"] ?? NSNull(),
            "userNotes": raw["userNotes"] as? String ?? "",
            "enhancedNotes": raw["enhancedNotes"] as? String ?? "",
            "createdAt": nowMillis,
            "updatedAt": nowMillis,
            "segments": [],
            "chatMessages": chatMessages,
            "hasAudio": raw["hasAudio"] as? Bool ?? false,
            "audioUrl": raw["audioUrl"] as Any? ?? NSNull(),
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func requestBodyData(from request: URLRequest) throws -> Data {
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

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else {
            throw URLError(.badServerResponse)
        }
        return self
    }
}
