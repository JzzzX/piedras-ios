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

        let newRecordingButton = app.buttons["NewRecordingButton"]
        XCTAssertTrue(newRecordingButton.waitForExistence(timeout: 10))
        newRecordingButton.tap()

        let stopButton = app.buttons["StopRecordingButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 12))

        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(2)

        app.activate()
        let reactivatedStopButton = app.buttons["StopRecordingButton"]
        XCTAssertTrue(reactivatedStopButton.waitForExistence(timeout: 12))

        let durationLabel = app.staticTexts["RecordDurationLabel"]
        XCTAssertTrue(durationLabel.waitForExistence(timeout: 5))

        reactivatedStopButton.tap()
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
