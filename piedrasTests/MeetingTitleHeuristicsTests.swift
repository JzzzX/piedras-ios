import Foundation
import Testing
@testable import piedras

struct MeetingTitleHeuristicsTests {
    @Test
    func usesKeyPhraseWhenTranscriptHasClearTopic() {
        let title = MeetingTitleHeuristics.fallbackTitle(
            transcript: "[麦克风]: 今天主要聊一下 KOL投放面试人小李技术面 的安排",
            finalSegmentCount: 2,
            durationSeconds: 180,
            meetingDate: Date(timeIntervalSince1970: 0)
        )

        #expect(title == "KOL投放面试人小李技术面")
    }

    @Test
    func usesVoiceMemoForShortRecordingWithoutUsefulTranscript() {
        let title = MeetingTitleHeuristics.fallbackTitle(
            transcript: "",
            finalSegmentCount: 0,
            durationSeconds: 34,
            meetingDate: Date(timeIntervalSince1970: 0)
        )

        #expect(title == "语音备忘 00:34")
    }

    @Test
    func usesRecordingDateForLowInformationTranscript() {
        let meetingDate = ISO8601DateFormatter().date(from: "2026-03-18T20:46:00+08:00") ?? .now
        let title = MeetingTitleHeuristics.fallbackTitle(
            transcript: "[麦克风]: 嗯 好",
            finalSegmentCount: 1,
            durationSeconds: 120,
            meetingDate: meetingDate
        )

        #expect(title == "3月18日 20:46 录音")
    }
}
