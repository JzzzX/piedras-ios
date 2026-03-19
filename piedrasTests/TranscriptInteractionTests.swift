import Foundation
import Testing
@testable import piedras

struct TranscriptInteractionTests {
    @Test
    func orderedSegmentsSortByOrderIndexThenStartTime() {
        let laterSegment = TranscriptSegment(
            id: "later",
            speaker: "Speaker 2",
            text: "第二段",
            startTime: 4_000,
            endTime: 7_000,
            orderIndex: 1
        )
        let earlierSegmentSameOrder = TranscriptSegment(
            id: "earlier",
            speaker: "Speaker 1",
            text: "第一段",
            startTime: 1_000,
            endTime: 3_000,
            orderIndex: 1
        )
        let highestPrioritySegment = TranscriptSegment(
            id: "top",
            speaker: "Speaker 0",
            text: "置顶段",
            startTime: 9_000,
            endTime: 10_000,
            orderIndex: 0
        )

        let meeting = Meeting(
            segments: [laterSegment, earlierSegmentSameOrder, highestPrioritySegment]
        )

        #expect(meeting.orderedSegments.map(\.id) == ["top", "earlier", "later"])
    }

    @Test
    func transcriptTextAndPreviewPreferCurrentDataSources() {
        let meeting = Meeting(
            userNotesPlainText: "",
            enhancedNotes: "",
            segments: [
                TranscriptSegment(
                    id: "s1",
                    speaker: "Speaker 1",
                    text: "第一行",
                    startTime: 0,
                    endTime: 1_000,
                    orderIndex: 0
                ),
                TranscriptSegment(
                    id: "s2",
                    speaker: "Speaker 2",
                    text: "第二行",
                    startTime: 1_000,
                    endTime: 2_000,
                    orderIndex: 1
                ),
            ]
        )

        #expect(meeting.transcriptText == "第一行\n第二行")
        #expect(meeting.previewText == "第一行\n第二行")
    }

    @Test
    func timeRangeLabelNormalizesMillisecondsAgainstBaseTime() {
        let segment = TranscriptSegment(
            speaker: "Speaker 1",
            text: "内容",
            startTime: 66_000,
            endTime: 71_000,
            orderIndex: 0
        )

        #expect(segment.timeRangeLabel(relativeTo: 60_000) == "6s - 11s")
    }
}
