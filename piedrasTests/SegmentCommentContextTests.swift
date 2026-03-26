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
}
