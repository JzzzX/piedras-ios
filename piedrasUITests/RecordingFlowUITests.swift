import XCTest

final class RecordingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordingContinuesAfterBackgrounding() throws {
        let app = XCUIApplication()
        app.launch()

        dismissPermissionAlertsIfNeeded(in: app)

        let backButton = app.buttons["BackButton"]
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
        }

        let newRecordingButton = app.buttons["新录音"]
        XCTAssertTrue(newRecordingButton.waitForExistence(timeout: 10))
        newRecordingButton.tap()

        let stopButton = app.buttons["停止"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 12))

        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(2)

        app.activate()
        XCTAssertTrue(app.buttons["停止"].waitForExistence(timeout: 12))

        let durationLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "录音时长 ")).firstMatch
        XCTAssertTrue(durationLabel.waitForExistence(timeout: 5))

        stopButton.tap()

        let restartButton = app.buttons["继续录音"]
        XCTAssertTrue(restartButton.waitForExistence(timeout: 12))
    }

    private func dismissPermissionAlertsIfNeeded(in app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            let candidateLabels = [
                "允许",
                "好",
                "OK",
                "Allow",
                "Allow While Using App",
            ]

            for label in candidateLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }

            if alert.buttons.firstMatch.exists {
                alert.buttons.firstMatch.tap()
                return true
            }

            return false
        }

        app.tap()
    }
}
