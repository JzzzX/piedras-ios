import UIKit

@MainActor
final class AppActivityCoordinator {
    private var isKeepingScreenAwake = false

    func setKeepScreenAwake(_ enabled: Bool) {
        guard isKeepingScreenAwake != enabled else {
            return
        }

        isKeepingScreenAwake = enabled
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    func performExpiringActivity(
        named name: String,
        operation: @escaping @MainActor () async -> Void
    ) async {
        var taskID = UIBackgroundTaskIdentifier.invalid

        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }

        await operation()

        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}
