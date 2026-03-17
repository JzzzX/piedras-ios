import XCTest

final class RecordingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordingContinuesAfterBackgrounding() throws {
        let app = launchApp()

        let homeChatField = app.textFields["HomeGlobalChatField"]
        XCTAssertTrue(homeChatField.waitForExistence(timeout: 8), "首页未正常加载。")

        let newRecordingButton = app.buttons["NewRecordingButton"]
        XCTAssertTrue(newRecordingButton.waitForExistence(timeout: 8), "首页录音入口未出现。")
        newRecordingButton.tap()

        dismissPermissionAlertsIfNeeded(in: app)
        app.tap()

        let stopButton = element(in: app, identifier: "StopRecordingButton", fallbackLabel: "停止录音")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 12), "开始录音后未进入录音态。")

        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(2)

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8), "应用回到前台失败。")
        app.tap()

        let reactivatedStopButton = element(in: app, identifier: "StopRecordingButton", fallbackLabel: "停止录音")
        XCTAssertTrue(reactivatedStopButton.waitForExistence(timeout: 12), "回到前台后录音态未恢复。")

        let durationLabel = element(in: app, identifier: "RecordDurationLabel")
        XCTAssertTrue(durationLabel.waitForExistence(timeout: 5), "录音时长未显示。")

        reactivatedStopButton.tap()
    }

    @MainActor
    func testHomeAIComposerOpensGlobalChat() throws {
        let app = launchApp()

        let field = app.textFields["HomeGlobalChatField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Summarize roadmap")

        let sendButton = app.buttons["HomeGlobalChatSendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 2))
        sendButton.tap()

        XCTAssertTrue(app.staticTexts["Summarize roadmap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["GlobalChatInputField"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMeetingRowSupportsSwipeToDelete() throws {
        let app = launchApp()
        let seededTitle = "Piedras iOS MVP Kickoff"

        let rows = app.descendants(matching: .any).matching(identifier: "MeetingRow")
        let firstRow = rows.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.swipeLeft()

        let deleteButton = app.buttons["删除"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "左滑后删除按钮未出现。")
        deleteButton.tap()

        let deletedTitle = app.staticTexts[seededTitle]
        let predicate = NSPredicate(format: "exists == false")
        expectation(for: predicate, evaluatedWith: deletedTitle)
        waitForExpectations(timeout: 5)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_IN_MEMORY")
        app.launch()
        return app
    }

    private func element(in app: XCUIApplication, identifier: String, fallbackLabel: String? = nil) -> XCUIElement {
        if let fallbackLabel {
            let predicate = NSPredicate(format: "identifier == %@ OR label == %@", identifier, fallbackLabel)
            return app.descendants(matching: .any)
                .matching(predicate)
                .firstMatch
        }

        return app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
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
