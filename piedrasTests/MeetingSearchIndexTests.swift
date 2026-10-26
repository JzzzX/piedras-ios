import Foundation
import Testing
@testable import piedras

struct MeetingSearchIndexTests {
    @Test
    func searchIndexTextIncludesSegmentComments() {
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们下周灰度上线。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(comment: "灰度范围只覆盖 iOS 内测用户。")
        annotation.segment = segment
        segment.annotation = annotation

        let meeting = Meeting(
            title: "灰度上线会",
            userNotesPlainText: "记录上线安排",
            enhancedNotes: "AI 已总结行动项",
            segments: [segment]
        )

        #expect(meeting.searchIndexText.contains("灰度范围只覆盖 ios 内测用户。"))
    }

    @Test
    func searchIndexTextIncludesAnnotationImageText() {
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "先看一下投影上的发布时间。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(
            comment: "",
            imageTextContext: "投影写着：4 月 8 日灰度，4 月 15 日全量。",
            imageTextStatus: .ready,
            imageTextUpdatedAt: .now
        )
        annotation.segment = segment
        segment.annotation = annotation

        let meeting = Meeting(
            title: "发布时间确认会",
            userNotesPlainText: "记录发布时间",
            enhancedNotes: "AI 已总结发布时间安排",
            segments: [segment]
        )

        #expect(meeting.searchIndexText.contains("投影写着：4 月 8 日灰度，4 月 15 日全量。"))
    }

    @Test
    func searchResultsMatchTokensAcrossEnhancedNotesAndImageTextSources() throws {
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们看一下路线图。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation(
            comment: "",
            imageTextContext: "路线图上写着 4 月 8 日发布。",
            imageTextStatus: .ready,
            imageTextUpdatedAt: .now
        )
        annotation.segment = segment
        segment.annotation = annotation

        let meeting = Meeting(
            title: "灰度上线会",
            userNotesPlainText: "记录发布时间",
            enhancedNotes: "AI 总结：路线图已确认发布时间。",
            segments: [segment]
        )

        let results = MeetingSearchIndexBuilder.searchResults(
            for: [meeting],
            query: "路线图 发布"
        )
        let result = try #require(results.first)

        #expect(result.matchedSources.contains(.enhancedNotes))
        #expect(result.matchedSources.contains(.imageText))
    }

    @Test
    func localRetrievalResultFiltersMeetingsByCollection() {
        let included = Meeting(
            title: "项目复盘",
            userNotesPlainText: "这里记录发布节奏和灰度安排。",
            collectionId: "collection-projects"
        )
        let excluded = Meeting(
            title: "私人杂项",
            userNotesPlainText: "这里也提到了发布节奏。",
            collectionId: "collection-personal"
        )

        let result = MeetingSearchIndexBuilder.localRetrievalResult(
            for: "发布节奏",
            meetings: [included, excluded],
            collectionID: "collection-projects"
        )

        #expect(result.context.contains("项目复盘"))
        #expect(!result.context.contains("私人杂项"))
        #expect(result.sources.map(\.title) == ["项目复盘"])
    }
}
