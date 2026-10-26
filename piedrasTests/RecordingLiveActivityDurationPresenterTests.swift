import Foundation
import Testing
@testable import piedras

struct RecordingLiveActivityDurationPresenterTests {
    @Test
    func recordingStateUsesLiveTimerWhenStartDateExists() {
        let startDate = Date(timeIntervalSince1970: 1_234)

        let display = RecordingLiveActivityDurationPresenter.display(
            for: .recording,
            durationSeconds: 42,
            timerStartDate: startDate
        )

        #expect(display == .liveTimer(startDate: startDate))
    }

    @Test
    func pausedStateFallsBackToStaticDurationText() {
        let display = RecordingLiveActivityDurationPresenter.display(
            for: .paused,
            durationSeconds: 125,
            timerStartDate: Date(timeIntervalSince1970: 1_234)
        )

        #expect(display == .staticText("02:05"))
    }

    @Test
    func recordingStateWithoutStartDateFallsBackToStaticDurationText() {
        let display = RecordingLiveActivityDurationPresenter.display(
            for: .recording,
            durationSeconds: 3_661,
            timerStartDate: nil
        )

        #expect(display == .staticText("1:01:01"))
    }

    @Test
    func compactDurationTextKeepsSecondsWhenUnderOneHour() {
        let text = RecordingLiveActivityDurationPresenter.compactText(durationSeconds: 125)

        #expect(text == "02:05")
    }

    @Test
    func compactDurationTextDropsSecondsAfterOneHourToStayShort() {
        let text = RecordingLiveActivityDurationPresenter.compactText(durationSeconds: 3_661)

        #expect(text == "1:01")
    }
}
