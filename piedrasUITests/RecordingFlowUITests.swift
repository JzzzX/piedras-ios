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
    func testInitialLaunchShowsHomeWithoutBackendPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_ISOLATED_DEFAULTS")
        app.launch()

        XCTAssertTrue(app.textFields["HomeGlobalChatField"].waitForExistence(timeout: 8), "首页未正常加载。")
        XCTAssertFalse(app.staticTexts["Connect your Mac backend first."].exists, "不应再展示本地后端配置引导。")
    }

    @MainActor
    func testHomeAIComposerOpensGlobalChat() throws {
        let app = launchApp()
        let question = "Summarize roadmap"

        let field = app.textFields["HomeGlobalChatField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(question)

        let sendButton = app.buttons["HomeGlobalChatSendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 2))
        sendButton.tap()

        let globalField = app.textFields["GlobalChatInputField"]
        XCTAssertTrue(globalField.waitForExistence(timeout: 5))
        XCTAssertEqual(globalField.value as? String, question)
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

    @MainActor
    func testMeetingDetailMenuShowsImmersiveActions() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        XCTAssertFalse(app.staticTexts["Piedras AI"].exists, "详情页不应再展示品牌标题。")
        XCTAssertTrue(app.buttons["MeetingModeTranscriptTab"].waitForExistence(timeout: 3), "缺少 Transcript 页签。")
        XCTAssertTrue(app.buttons["MeetingModeSummaryTab"].exists, "缺少 AI Notes 页签。")

        app.buttons["MeetingModeSummaryTab"].tap()
        XCTAssertTrue(app.buttons["MeetingAskButton"].waitForExistence(timeout: 3), "AI Notes 页缺少 Ask 入口。")

        let moreButton = app.buttons["MeetingDetailMoreButton"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "详情页更多按钮未出现。")
        moreButton.tap()

        XCTAssertTrue(app.buttons["Edit title"].waitForExistence(timeout: 2), "缺少 Edit title 动作。")
        XCTAssertTrue(app.buttons["Show my notes"].exists, "缺少 Show my notes 动作。")
        XCTAssertTrue(app.buttons["Copy notes"].exists, "缺少 Copy notes 动作。")
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
