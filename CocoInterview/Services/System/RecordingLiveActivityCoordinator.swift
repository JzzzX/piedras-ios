import ActivityKit
import Foundation

struct RecordingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: RecordingLiveActivityPhase
        var durationSeconds: Int
        var timerStartDate: Date?
    }

    var meetingID: String
}

@MainActor
protocol RecordingLiveActivityCoordinating: AnyObject {
    func start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int)
    func update(phase: RecordingLiveActivityPhase, durationSeconds: Int)
    func end()
}

@MainActor
final class RecordingLiveActivityCoordinator: RecordingLiveActivityCoordinating {
    private var activity: Activity<RecordingLiveActivityAttributes>?
    private var activeMeetingID: String?
    private var latestPhase: RecordingLiveActivityPhase = .recording
    private var latestDurationSeconds = 0

    func start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int) {
        latestPhase = phase
        latestDurationSeconds = max(durationSeconds, 0)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activity = nil
            activeMeetingID = nil
            return
        }

        if activeMeetingID == meetingID, activity != nil {
            update(phase: phase, durationSeconds: durationSeconds)
            return
        }

        end()

        let attributes = RecordingLiveActivityAttributes(meetingID: meetingID)
        let content = ActivityContent(
            state: makeContentState(phase: phase, durationSeconds: durationSeconds),
            staleDate: nil
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activeMeetingID = meetingID
        } catch {
            activity = nil
            activeMeetingID = nil
        }
    }

    func update(phase: RecordingLiveActivityPhase, durationSeconds: Int) {
        latestPhase = phase
        latestDurationSeconds = max(durationSeconds, 0)

        guard let activity else { return }
        let content = ActivityContent(
            state: makeContentState(phase: phase, durationSeconds: durationSeconds),
            staleDate: nil
        )

        Task {
            await activity.update(content)
        }
    }

    func end() {
        guard let activity else {
            activeMeetingID = nil
            return
        }

        let content = ActivityContent(
            state: makeContentState(phase: latestPhase, durationSeconds: latestDurationSeconds),
            staleDate: .now
        )

        self.activity = nil
        activeMeetingID = nil

        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private func makeContentState(
        phase: RecordingLiveActivityPhase,
        durationSeconds: Int
    ) -> RecordingLiveActivityAttributes.ContentState {
        let normalizedDuration = max(durationSeconds, 0)
        let timerStartDate = phase == .recording
            ? Date().addingTimeInterval(TimeInterval(-normalizedDuration))
            : nil

        return RecordingLiveActivityAttributes.ContentState(
            phase: phase,
            durationSeconds: normalizedDuration,
            timerStartDate: timerStartDate
        )
    }
}
