import Foundation
import SwiftData
import Testing
@testable import piedras

struct MeetingAnnotationSyncTests {
    @MainActor
    @Test
    func applyingRemoteMeetingPreservesExistingSegmentAnnotationWhenSegmentIDMatches() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)

        let meeting = Meeting(
            title: "带标注的会议",
            enhancedNotes: "旧 AI 笔记"
        )
        let segment = TranscriptSegment(
            id: "segment-1",
            speaker: "Speaker A",
            text: "原始转写",
            startTime: 1_000,
            endTime: 2_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(
            comment: "这是一条本地评论",
            imageFileNames: ["photo-1.jpg"],
            imageTextContext: "白板上写着发布时间",
            imageTextStatus: .ready,
            imageTextUpdatedAt: .now
        )
        annotation.segment = segment
        segment.annotation = annotation
        segment.meeting = meeting
        meeting.segments = [segment]
        repository.insert(meeting)
        try repository.save()

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
            enhancedNotes: "新的 AI 笔记",
            noteAttachments: [
                RemoteMeetingAttachment(
                    id: "attachment-1",
                    mimeType: "image/jpeg",
                    url: "/api/meetings/\(meeting.id)/attachments/attachment-1",
                    originalName: "whiteboard.jpg",
                    extractedText: "白板重点",
                    createdAt: meeting.createdAt,
                    updatedAt: meeting.updatedAt
                )
            ],
            noteAttachmentsTextContext: "白板重点",
            createdAt: meeting.createdAt,
            updatedAt: meeting.updatedAt.addingTimeInterval(10),
            workspaceId: meeting.hiddenWorkspaceId,
            speakers: nil,
            segments: [
                RemoteTranscriptSegment(
                    id: "segment-1",
                    speaker: "Speaker A",
                    text: "原始转写",
                    startTime: 1_000,
                    endTime: 2_000,
                    isFinal: true,
                    order: 0
                )
            ],
            chatMessages: [],
            audioCloudSyncEnabled: false,
            hasAudio: false,
            audioUrl: nil,
            audioProcessingState: nil,
            audioProcessingError: nil,
            audioProcessingAttempts: nil,
            audioProcessingRequestedAt: nil,
            audioProcessingStartedAt: nil,
            audioProcessingCompletedAt: nil
        )

        MeetingPayloadMapper.apply(
            remote: remote,
            to: meeting,
            repository: repository,
            baseURL: nil
        )

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        let refreshedSegment = try #require(refreshedMeeting.orderedSegments.only)
        let refreshedAnnotation = try #require(refreshedSegment.annotation)

        #expect(refreshedMeeting.enhancedNotes == "新的 AI 笔记")
        #expect(refreshedMeeting.audioCloudSyncEnabled == false)
        #expect(refreshedMeeting.noteAttachmentTextContext == "白板重点")
        #expect(refreshedAnnotation.comment == "这是一条本地评论")
        #expect(refreshedAnnotation.imageFileNames == ["photo-1.jpg"])
        #expect(refreshedAnnotation.imageTextContext == "白板上写着发布时间")
    }

    @MainActor
    @Test
    func applyingRemoteMeetingWithEmptySegmentsPreservesLocalTranscript() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)

        let meeting = Meeting(
            title: "本地优先转写",
            enhancedNotes: "旧 AI 笔记"
        )
        let segment = TranscriptSegment(
            id: "segment-local-1",
            speaker: "麦克风",
            text: "这段本地转写不能被远端空数据抹掉",
            startTime: 0,
            endTime: 1_500,
            orderIndex: 0
        )
        segment.meeting = meeting
        meeting.segments = [segment]
        repository.insert(meeting)
        try repository.save()

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
            noteAttachments: [],
            noteAttachmentsTextContext: nil,
            createdAt: meeting.createdAt,
            updatedAt: meeting.updatedAt.addingTimeInterval(10),
            workspaceId: meeting.hiddenWorkspaceId,
            speakers: [:],
            segments: [],
            chatMessages: [],
            audioCloudSyncEnabled: true,
            hasAudio: true,
            audioUrl: "/api/meetings/\(meeting.id)/audio?t=123",
            audioProcessingState: "idle",
            audioProcessingError: nil,
            audioProcessingAttempts: 0,
            audioProcessingRequestedAt: nil,
            audioProcessingStartedAt: nil,
            audioProcessingCompletedAt: nil
        )

        MeetingPayloadMapper.applyRemoteSyncState(
            remote: remote,
            to: meeting,
            repository: repository,
            baseURL: URL(string: "https://example.com")
        )

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["这段本地转写不能被远端空数据抹掉"])
        #expect(refreshedMeeting.audioRemotePath == "https://example.com/api/meetings/\(meeting.id)/audio?t=123")
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
