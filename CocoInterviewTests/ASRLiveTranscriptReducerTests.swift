import Foundation
import Testing
@testable import CocoInterview

struct ASRLiveTranscriptReducerTests {
    @Test
    func keepsLatestSentenceAsProvisionalAndOnlyCommitsStablePrefix() {
        var reducer = ASRLiveTranscriptReducer()

        let firstPassCommits = reducer.apply(
            ASRRecognitionSnapshot(
                revision: 1,
                fullText: "产品评审",
                audioEndTimeMs: 900,
                utterances: [
                    ASRRecognitionUtterance(
                        text: "产品评审",
                        startTimeMs: 0,
                        endTimeMs: 900,
                        definite: false
                    )
                ]
            )
        )

        #expect(firstPassCommits.isEmpty)
        #expect(reducer.provisionalTail?.text == "产品评审")

        let secondPassCommits = reducer.apply(
            ASRRecognitionSnapshot(
                revision: 2,
                fullText: "产品评审 下一步确认排期",
                audioEndTimeMs: 2200,
                utterances: [
                    ASRRecognitionUtterance(
                        text: "产品评审",
                        startTimeMs: 0,
                        endTimeMs: 900,
                        definite: true
                    ),
                    ASRRecognitionUtterance(
                        text: "下一步确认排期",
                        startTimeMs: 1000,
                        endTimeMs: 2200,
                        definite: false
                    ),
                ]
            )
        )

        #expect(secondPassCommits.count == 1)
        #expect(secondPassCommits[0].text == "产品评审")
        #expect(reducer.provisionalTail?.text == "下一步确认排期")
    }

    @Test
    func revisesTailInPlaceAndIgnoresOutdatedRevision() {
        var reducer = ASRLiveTranscriptReducer()

        _ = reducer.apply(
            ASRRecognitionSnapshot(
                revision: 3,
                fullText: "然后确认版本节奏",
                audioEndTimeMs: 1600,
                utterances: [
                    ASRRecognitionUtterance(
                        text: "然后确认版本节奏",
                        startTimeMs: 0,
                        endTimeMs: 1600,
                        definite: false
                    )
                ]
            )
        )

        let outdatedCommits = reducer.apply(
            ASRRecognitionSnapshot(
                revision: 2,
                fullText: "然后确认版本",
                audioEndTimeMs: 1300,
                utterances: [
                    ASRRecognitionUtterance(
                        text: "然后确认版本",
                        startTimeMs: 0,
                        endTimeMs: 1300,
                        definite: false
                    )
                ]
            )
        )

        #expect(outdatedCommits.isEmpty)
        #expect(reducer.provisionalTail?.text == "然后确认版本节奏")

        let revisedCommits = reducer.apply(
            ASRRecognitionSnapshot(
                revision: 4,
                fullText: "然后确认发布节奏",
                audioEndTimeMs: 1700,
                utterances: [
                    ASRRecognitionUtterance(
                        text: "然后确认发布节奏",
                        startTimeMs: 0,
                        endTimeMs: 1700,
                        definite: false
                    )
                ]
            )
        )

        #expect(revisedCommits.isEmpty)
        #expect(reducer.provisionalTail?.text == "然后确认发布节奏")
    }

    @Test
    func flushesRemainingTailWhenStreamingStops() {
        var reducer = ASRLiveTranscriptReducer()

        _ = reducer.apply(
            ASRRecognitionSnapshot(
                revision: 5,
                fullText: "收尾确认负责人",
                audioEndTimeMs: 1800,
                utterances: [
                    ASRRecognitionUtterance(
                        text: "收尾确认负责人",
                        startTimeMs: 0,
                        endTimeMs: 1800,
                        definite: true
                    )
                ]
            )
        )

        let flushed = reducer.flushRemainingTail()

        #expect(flushed?.text == "收尾确认负责人")
        #expect(reducer.provisionalTail == nil)
    }
}
