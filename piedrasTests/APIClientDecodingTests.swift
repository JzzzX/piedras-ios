import Foundation
import Testing
@testable import piedras

struct APIClientDecodingTests {
    private let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @Test
    func decodesRemoteMeetingDetailWithNumericChatTimestamp() throws {
        let payload = """
        {
          "id": "meeting-1",
          "title": "Weekly sync",
          "date": "2026-03-19T08:45:00.000Z",
          "status": "ended",
          "duration": 120,
          "audioMimeType": "audio/m4a",
          "audioDuration": 120,
          "audioUpdatedAt": "2026-03-19T08:47:00.000Z",
          "userNotes": "<p>Notes</p>",
          "enhancedNotes": "summary",
          "createdAt": "2026-03-19T08:40:00.000Z",
          "updatedAt": "2026-03-19T08:47:00.000Z",
          "workspaceId": "workspace-1",
          "segments": [],
          "chatMessages": [
            {
              "id": "chat-1",
              "role": "assistant",
              "content": "Hello",
              "timestamp": 1773901562841
            }
          ],
          "hasAudio": true,
          "audioUrl": "/api/meetings/meeting-1/audio"
        }
        """

        let meeting = try APIClient.makeJSONDecoder().decode(
            RemoteMeetingDetail.self,
            from: Data(payload.utf8)
        )

        #expect(meeting.chatMessages.count == 1)
        #expect(Int(meeting.chatMessages[0].timestamp.timeIntervalSince1970) == 1_773_901_562)
    }

    @Test
    func decodesRemoteMeetingDetailWithISO8601ChatTimestamp() throws {
        let payload = """
        {
          "id": "meeting-2",
          "title": "Interview",
          "date": "2026-03-19T09:15:00.000Z",
          "status": "ended",
          "duration": 95,
          "audioMimeType": null,
          "audioDuration": null,
          "audioUpdatedAt": null,
          "userNotes": "",
          "enhancedNotes": "",
          "createdAt": "2026-03-19T09:10:00.000Z",
          "updatedAt": "2026-03-19T09:20:00.000Z",
          "workspaceId": "workspace-1",
          "segments": [],
          "chatMessages": [
            {
              "id": "chat-2",
              "role": "user",
              "content": "Question",
              "timestamp": "2026-03-19T09:19:00.000Z"
            }
          ],
          "hasAudio": false,
          "audioUrl": null
        }
        """

        let meeting = try APIClient.makeJSONDecoder().decode(
            RemoteMeetingDetail.self,
            from: Data(payload.utf8)
        )

        #expect(meeting.chatMessages.count == 1)
        #expect(meeting.chatMessages[0].timestamp == fractionalFormatter.date(from: "2026-03-19T09:19:00.000Z"))
    }

    @MainActor
    @Test
    func buildsStructuredBackendErrorMessageWithRequestID() {
        let payload = """
        {
          "error": "AI 后处理失败：上游超时",
          "requestId": "rid-123",
          "route": "/api/enhance"
        }
        """

        let message = APIClient.buildErrorMessage(from: Data(payload.utf8))

        #expect(message == "AI 后处理失败：上游超时 [RID: rid-123]")
    }

    @MainActor
    @Test
    func buildsBackendErrorMessageFromHeaderWhenBodyHasNoRequestID() throws {
        let payload = """
        {
          "error": "保存会议失败：数据库不可用"
        }
        """
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.com/api/meetings")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["X-Request-Id": "rid-456"]
            )
        )

        let message = APIClient.buildErrorMessage(
            from: Data(payload.utf8),
            response: response
        )

        #expect(message == "保存会议失败：数据库不可用 [RID: rid-456]")
    }

    @MainActor
    @Test
    func buildsDeleteFallbackMessageWithHTTPStatusAndRequestID() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.com/api/meetings/meeting-1")!,
                statusCode: 502,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/html",
                    "X-Request-Id": "rid-789",
                ]
            )
        )

        let message = APIClient.buildErrorMessage(
            from: Data("<!DOCTYPE html><html><body>Bad Gateway</body></html>".utf8),
            response: response,
            fallback: "删除会议失败。"
        )

        #expect(message == "删除会议失败（HTTP 502） [RID: rid-789]")
    }
}
