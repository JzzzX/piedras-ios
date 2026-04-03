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
          "audioEnhancedNotes": "audio summary",
          "audioEnhancedNotesStatus": "ready",
          "audioEnhancedNotesError": "",
          "audioEnhancedNotesUpdatedAt": "2026-03-19T08:48:00.000Z",
          "audioEnhancedNotesProvider": "openai",
          "audioEnhancedNotesModel": "gemini-3-flash-preview",
          "createdAt": "2026-03-19T08:40:00.000Z",
          "updatedAt": "2026-03-19T08:47:00.000Z",
          "workspaceId": "workspace-1",
          "collectionId": "collection-notes",
          "audioCloudSyncEnabled": false,
          "noteAttachments": [
            {
              "id": "attachment-1",
              "mimeType": "image/jpeg",
              "url": "/api/meetings/meeting-1/attachments/attachment-1",
              "originalName": "whiteboard.jpg",
              "extractedText": "白板重点",
              "createdAt": "2026-03-19T08:46:00.000Z",
              "updatedAt": "2026-03-19T08:46:30.000Z"
            }
          ],
          "noteAttachmentsTextContext": "白板重点",
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
        #expect(meeting.audioEnhancedNotes == "audio summary")
        #expect(meeting.audioEnhancedNotesStatus == "ready")
        #expect(meeting.audioEnhancedNotesProvider == "openai")
        #expect(meeting.collectionId == "collection-notes")
        #expect(meeting.audioCloudSyncEnabled == false)
        #expect(meeting.noteAttachments?.count == 1)
        #expect(meeting.noteAttachmentsTextContext == "白板重点")
    }

    @Test
    func decodesRemoteCollectionPayload() throws {
        let payload = """
        {
          "id": "collection-notes",
          "name": "Notes",
          "isDefault": true
        }
        """

        let collection = try APIClient.makeJSONDecoder().decode(
            RemoteCollection.self,
            from: Data(payload.utf8)
        )

        #expect(collection.id == "collection-notes")
        #expect(collection.name == "Notes")
        #expect(collection.isDefault == true)
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

    @Test
    func decodesAudioEnhanceStatusPayload() throws {
        let payload = """
        {
          "meetingId": "meeting-3",
          "hasAudio": true,
          "audioEnhancedNotes": "音频总结",
          "audioEnhancedNotesStatus": "processing",
          "audioEnhancedNotesError": null,
          "audioEnhancedNotesUpdatedAt": "2026-03-31T09:00:00.000Z",
          "audioEnhancedNotesProvider": "openai",
          "audioEnhancedNotesModel": "gpt-4.1",
          "audioEnhancedNotesAttempts": 1,
          "audioEnhancedNotesRequestedAt": "2026-03-31T08:59:00.000Z",
          "audioEnhancedNotesStartedAt": "2026-03-31T08:59:02.000Z"
        }
        """

        let status = try APIClient.makeJSONDecoder().decode(
            RemoteAudioEnhanceStatusResponse.self,
            from: Data(payload.utf8)
        )

        #expect(status.meetingId == "meeting-3")
        #expect(status.audioEnhancedNotesStatus == "processing")
        #expect(status.audioEnhancedNotesAttempts == 1)
        #expect(status.audioEnhancedNotesProvider == "openai")
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
