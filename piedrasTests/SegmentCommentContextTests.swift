import Foundation
import Testing
@testable import piedras

struct SegmentCommentContextTests {
    @Test
    func enhancePayloadIncludesMeetingPromptOptions() throws {
        let meeting = Meeting(
            title: "用户访谈",
            userNotesPlainText: "重点问了首购转化和退款原因。",
            segments: [
                TranscriptSegment(
                    speaker: "Speaker A",
                    text: "我来负责下周五前整理访谈报告。",
                    startTime: 3_000,
                    endTime: 8_000,
                    orderIndex: 0
                )
            ]
        )
        meeting.meetingType = MeetingTypeOption.interview.rawValue

        let payload = MeetingPayloadMapper.makeEnhancePayload(from: meeting)
        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let promptOptions = try #require(json["promptOptions"] as? [String: Any])

        #expect(promptOptions["meetingType"] as? String == "访谈")
        #expect(promptOptions["outputStyle"] as? String == "平衡")
        #expect(promptOptions["includeActionItems"] as? Bool == true)
    }

    @Test
    func enhancePayloadIncludesMeetingNoteAttachmentsContext() throws {
        let meeting = Meeting(
            title: "白板拍照整理",
            userNotesPlainText: "结合白板内容整理方案。"
        )
        meeting.noteAttachmentFileNames = ["board.jpg"]
        meeting.noteAttachmentTextContext = "图片1：\n白板写着：4 月 8 日灰度，4 月 15 日全量。"
        meeting.noteAttachmentTextStatus = .ready
        meeting.noteAttachmentTextUpdatedAt = .now

        let payload = MeetingPayloadMapper.makeEnhancePayload(from: meeting)
        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let context = try #require(json["noteAttachmentsContext"] as? String)

        #expect(context.contains("--- 主笔记附件资料 ---"))
        #expect(context.contains("图片1："))
        #expect(context.contains("4 月 8 日灰度"))
    }

    @Test
    func enhancePayloadIncludesOrderedSegmentCommentsContext() throws {
        let meeting = makeMeetingWithComments()

        let payload = MeetingPayloadMapper.makeEnhancePayload(from: meeting)
        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let context = try #require(json["segmentCommentsContext"] as? String)

        #expect(context.contains("--- 转写片段评论 ---"))
        #expect(context.contains("[00:12] 原句：我们下周先灰度上线。"))
        #expect(context.contains("评论：这里的“下周”其实指 4 月第一周。"))
        #expect(context.contains("[00:35] 原句：图片 OCR 先不做。"))
        #expect(context.contains("评论：这是当前阶段结论，不代表永远不做。"))
        #expect(!context.contains("空白评论不应该进入上下文"))
    }

    @Test
    func meetingChatPayloadIncludesSameSegmentCommentsContext() throws {
        let meeting = makeMeetingWithComments()
        let session = ChatSession(
            scope: .meeting,
            title: "追问",
            messages: [
                ChatMessage(role: "user", content: "先总结一下", orderIndex: 0),
                ChatMessage(role: "assistant", content: "这里是旧回答", orderIndex: 1),
            ]
        )

        let payload = MeetingPayloadMapper.makeChatPayload(
            from: meeting,
            session: session,
            question: "继续追问"
        )

        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let context = try #require(json["segmentCommentsContext"] as? String)

        #expect(context.contains("[00:12] 原句：我们下周先灰度上线。"))
        #expect(context.contains("评论：这里的“下周”其实指 4 月第一周。"))
        #expect((json["chatHistory"] as? [[String: Any]])?.count == 2)
    }

    @Test
    func meetingChatPayloadIncludesMeetingNoteAttachmentsContext() throws {
        let meeting = Meeting(
            title: "附件问答测试",
            userNotesPlainText: "用户笔记只写了要看附件。",
            enhancedNotes: "AI 笔记里没有发布时间。"
        )
        meeting.noteAttachmentFileNames = ["timeline.png"]
        meeting.noteAttachmentTextContext = "图片1：\n路线图写着：4 月 8 日灰度，4 月 15 日全量。"
        meeting.noteAttachmentTextStatus = .ready
        meeting.noteAttachmentTextUpdatedAt = .now

        let payload = MeetingPayloadMapper.makeChatPayload(
            from: meeting,
            question: "发布时间是什么？"
        )

        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let context = try #require(json["noteAttachmentsContext"] as? String)

        #expect(context.contains("--- 主笔记附件资料 ---"))
        #expect(context.contains("图片1："))
        #expect(context.contains("4 月 8 日灰度"))
    }

    @Test
    func audioEnhancePayloadExcludesTranscriptButKeepsNotesAttachmentsAndComments() throws {
        let meeting = makeMeetingWithComments()
        meeting.userNotesPlainText = "用户笔记补充：先灰度一周再全量。"
        meeting.noteAttachmentFileNames = ["timeline.png"]
        meeting.noteAttachmentTextContext = "图片1：\n路线图写着：4 月 8 日灰度，4 月 15 日全量。"
        meeting.noteAttachmentTextStatus = .ready
        meeting.noteAttachmentTextUpdatedAt = .now

        let payload = MeetingPayloadMapper.makeAudioEnhancePayload(from: meeting)
        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect((json["userNotes"] as? String) == "用户笔记补充：先灰度一周再全量。")
        #expect((json["noteAttachmentsContext"] as? String)?.contains("--- 主笔记附件资料 ---") == true)
        #expect((json["segmentCommentsContext"] as? String)?.contains("--- 转写片段评论 ---") == true)
        #expect(json["transcript"] == nil)
    }

    @Test
    func segmentCommentsContextIncludesImageTextEvenWithoutTypedComment() throws {
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "先看一下白板上的发布时间。",
            startTime: 9_000,
            endTime: 12_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(
            comment: "   ",
            imageTextContext: "白板写着：4 月 8 日开始灰度，4 月 15 日全量。",
            imageTextStatus: .ready,
            imageTextUpdatedAt: .now
        )
        annotation.segment = segment
        segment.annotation = annotation

        let meeting = Meeting(
            title: "图片上下文测试",
            segments: [segment]
        )

        let context = MeetingCommentContextBuilder.segmentCommentsContext(for: meeting)

        #expect(context.contains("[00:09] 原句：先看一下白板上的发布时间。"))
        #expect(context.contains("图片文字：白板写着：4 月 8 日开始灰度，4 月 15 日全量。"))
    }

    @Test
    func localCommentContextFiltersMeetingsByCollection() {
        let includedMeeting = Meeting(
            title: "项目例会",
            collectionId: "collection-projects",
            segments: [commentedSegment(text: "项目发布时间是 4 月 8 日。", comment: "这是项目文件夹里的评论。")]
        )
        let excludedMeeting = Meeting(
            title: "私人笔记",
            collectionId: "collection-personal",
            segments: [commentedSegment(text: "私人安排在 4 月 9 日。", comment: "这是其他文件夹里的评论。")]
        )

        let context = MeetingCommentContextBuilder.localCommentContext(
            for: "发布时间",
            meetings: [includedMeeting, excludedMeeting],
            collectionID: "collection-projects"
        )

        #expect(context.contains("项目例会"))
        #expect(context.contains("这是项目文件夹里的评论。"))
        #expect(!context.contains("私人笔记"))
        #expect(!context.contains("这是其他文件夹里的评论。"))
    }

    private func makeMeetingWithComments() -> Meeting {
        let firstSegment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们下周先灰度上线。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let firstAnnotation = SegmentAnnotation(comment: "这里的“下周”其实指 4 月第一周。")
        firstAnnotation.segment = firstSegment
        firstSegment.annotation = firstAnnotation

        let secondSegment = TranscriptSegment(
            speaker: "Speaker B",
            text: "图片 OCR 先不做。",
            startTime: 35_000,
            endTime: 39_000,
            orderIndex: 1
        )
        let secondAnnotation = SegmentAnnotation(
            comment: "这是当前阶段结论，不代表永远不做。",
            imageTextContext: "路线图写着：4 月 8 日灰度发布。",
            imageTextStatus: .ready,
            imageTextUpdatedAt: .now
        )
        secondAnnotation.segment = secondSegment
        secondSegment.annotation = secondAnnotation

        let thirdSegment = TranscriptSegment(
            speaker: "Speaker C",
            text: "这个空白评论不应该进入上下文。",
            startTime: 58_000,
            endTime: 62_000,
            orderIndex: 2
        )
        let thirdAnnotation = SegmentAnnotation(comment: "   ")
        thirdAnnotation.segment = thirdSegment
        thirdSegment.annotation = thirdAnnotation

        return Meeting(
            title: "转写评论测试会议",
            userNotesPlainText: "用户笔记",
            enhancedNotes: "AI 笔记",
            segments: [firstSegment, secondSegment, thirdSegment]
        )
    }

    private func commentedSegment(text: String, comment: String) -> TranscriptSegment {
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: text,
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(comment: comment)
        annotation.segment = segment
        segment.annotation = annotation
        return segment
    }
}
