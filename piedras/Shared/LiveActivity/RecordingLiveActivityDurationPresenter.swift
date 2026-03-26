import Foundation

enum RecordingLiveActivityDurationDisplay: Equatable {
    case liveTimer(startDate: Date)
    case staticText(String)
}

enum RecordingLiveActivityDurationPresenter {
    static func display(
        for phase: RecordingLiveActivityPhase,
        durationSeconds: Int,
        timerStartDate: Date?
    ) -> RecordingLiveActivityDurationDisplay {
        if phase == .recording, let timerStartDate {
            return .liveTimer(startDate: timerStartDate)
        }

        return .staticText(formattedDuration(seconds: durationSeconds))
    }

    static func compactText(durationSeconds: Int) -> String {
        let totalSeconds = max(durationSeconds, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }

    static func formattedDuration(seconds: Int) -> String {
        let totalSeconds = max(seconds, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }
}
