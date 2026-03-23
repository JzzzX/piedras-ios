import XCTest

final class RecordingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordingContinuesAfterBackgrounding() throws {
        let app = launchApp()

        let homeChatLauncher = app.buttons["HomeGlobalChatLauncher"]
        XCTAssertTrue(homeChatLauncher.waitForExistence(timeout: 8), "首页未正常加载。")

        let newRecordingButton = element(in: app, identifier: "NewRecordingButton", fallbackLabel: "新录音")
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

        XCTAssertTrue(app.buttons["HomeGlobalChatLauncher"].waitForExistence(timeout: 8), "首页未正常加载。")
        XCTAssertFalse(app.staticTexts["Connect your Mac backend first."].exists, "不应再展示本地后端配置引导。")
    }

    @MainActor
    func testHomeChatLauncherOpensGlobalChat() throws {
        let app = launchApp()
        let launcher = app.buttons["HomeGlobalChatLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 5))
        launcher.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let globalField = app.textFields["GlobalChatInputField"]
        XCTAssertTrue(globalField.waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.otherElements["HomeErrorBanner"].exists, "本地删除成功后不应再展示错误横幅。")
    }

    @MainActor
    func testMeetingDetailSupportsEdgeSwipeBack() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let transcriptTab = app.buttons["MeetingModeTranscriptTab"]
        XCTAssertTrue(transcriptTab.waitForExistence(timeout: 3), "详情页未正常打开。")

        edgeSwipeBack(in: app)

        let homeLauncher = app.buttons["HomeGlobalChatLauncher"]
        XCTAssertTrue(homeLauncher.waitForExistence(timeout: 5), "右滑返回后应回到首页。")
        XCTAssertFalse(transcriptTab.exists, "右滑返回后不应仍停留在详情页。")
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
        XCTAssertTrue(app.staticTexts.matching(identifier: "TranscriptTimestamp").firstMatch.waitForExistence(timeout: 3), "Transcript 缺少时间戳。")

        app.buttons["MeetingModeSummaryTab"].tap()
        XCTAssertTrue(app.buttons["MeetingAskButton"].waitForExistence(timeout: 3), "AI Notes 页缺少 Chat with note 入口。")
        XCTAssertTrue(app.staticTexts["MeetingAskButtonGlyph"].exists, "与笔记对话入口应展示简易符号。")
        XCTAssertTrue(app.otherElements["EnhancedNotesRenderedView"].waitForExistence(timeout: 3), "AI Notes 应默认展示渲染后的文稿。")
        XCTAssertFalse(app.staticTexts["## 会议摘要"].exists, "AI Notes 默认页不应暴露原始 markdown 标记。")

        let moreButton = app.buttons["MeetingDetailMoreButton"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "详情页更多按钮未出现。")
        moreButton.tap()

        XCTAssertTrue(app.otherElements["MeetingDetailActionMenu"].waitForExistence(timeout: 2), "详情页操作菜单未出现。")
        XCTAssertTrue(app.buttons["MeetingDetailActionEditAINotes"].exists, "缺少 Edit AI notes 动作。")
        XCTAssertTrue(app.buttons["MeetingDetailActionCopyNotes"].exists, "缺少 Copy notes 动作。")
        XCTAssertFalse(app.buttons["MeetingDetailActionEditTitle"].exists, "Edit title 不应再出现在菜单里。")
        XCTAssertFalse(app.buttons["MeetingDetailActionShowMyNotes"].exists, "Show my notes 不应再出现在菜单里。")
        XCTAssertFalse(app.buttons["MeetingDetailActionViewAINotes"].exists, "AI Notes 菜单不应再出现 View AI notes。")

        app.buttons["MeetingDetailActionEditAINotes"].tap()
        XCTAssertTrue(app.textViews["EnhancedNotesMarkdownEditor"].waitForExistence(timeout: 3), "应能进入原始 markdown 编辑界面。")
        XCTAssertTrue(app.buttons["EnhancedNotesEditorCancelButton"].exists, "缺少 Cancel 操作。")
        XCTAssertTrue(app.buttons["EnhancedNotesEditorSaveButton"].exists, "缺少 Save 操作。")

        app.buttons["EnhancedNotesEditorCancelButton"].tap()
        XCTAssertTrue(app.otherElements["EnhancedNotesRenderedView"].waitForExistence(timeout: 3), "取消后应返回渲染态 AI Notes。")
    }

    @MainActor
    func testMeetingDetailSummaryTitleRenamesFromInlineDialog() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        app.buttons["MeetingModeSummaryTab"].tap()

        let titleTrigger = app.buttons["MeetingDetailTitleButton"]
        XCTAssertTrue(titleTrigger.waitForExistence(timeout: 3), "AI Notes 页标题区域应支持直接改名。")
        let initialTitle = app.staticTexts["MeetingDetailTitleText"].label
        titleTrigger.tap()

        XCTAssertTrue(app.otherElements["TitleRenameDialog"].waitForExistence(timeout: 3), "点击标题后应打开轻量重命名弹窗。")

        let field = app.textFields["TitleRenameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2), "重命名弹窗缺少输入框。")
        field.tap()
        field.typeText(" Draft")

        let saveButton = app.buttons["TitleRenameSaveButton"]
        XCTAssertTrue(saveButton.exists, "重命名弹窗缺少保存按钮。")
        saveButton.tap()

        let updatedTitle = app.staticTexts["MeetingDetailTitleText"]
        XCTAssertTrue(updatedTitle.waitForExistence(timeout: 3), "保存后标题文本应继续存在。")
        let titleUpdated = NSPredicate(format: "label CONTAINS %@ AND label != %@", "Draft", initialTitle)
        expectation(for: titleUpdated, evaluatedWith: updatedTitle)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.otherElements["TitleRenameDialog"].exists, "保存后弹窗应关闭。")
    }

    @MainActor
    func testMeetingDetailMenuDismissesWithoutTriggeringUnderlyingAction() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        app.buttons["MeetingModeSummaryTab"].tap()

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "AI Notes 页缺少 Chat with note 入口。")

        let moreButton = app.buttons["MeetingDetailMoreButton"]
        moreButton.tap()

        XCTAssertTrue(app.otherElements["MeetingDetailActionMenu"].waitForExistence(timeout: 2), "详情页操作菜单未出现。")

        askButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let menuDismissed = NSPredicate(format: "exists == false")
        expectation(for: menuDismissed, evaluatedWith: app.otherElements["MeetingDetailActionMenu"])
        waitForExpectations(timeout: 3)

        XCTAssertFalse(app.otherElements["SecondarySheetPanel"].exists, "点菜单外空白不应触发底部 Chat with note。")
        XCTAssertTrue(askButton.exists, "关闭菜单后应仍停留在详情页。")
    }

    @MainActor
    func testTranscriptNotesTeaserOpensDrawerAndPersistsDraft() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let transcriptTab = app.buttons["MeetingModeTranscriptTab"]
        XCTAssertTrue(transcriptTab.waitForExistence(timeout: 3), "详情页未正常打开。")
        transcriptTab.tap()

        let teaser = app.buttons["MeetingTranscriptNotesTeaser"]
        XCTAssertTrue(teaser.waitForExistence(timeout: 3), "Transcript 页应显示我的笔记预览入口。")
        XCTAssertTrue(app.staticTexts["MeetingTranscriptNotesTeaserGlyph"].exists, "我的笔记入口应展示简易符号。")
        teaser.tap()

        let drawer = app.otherElements["MeetingNotesDrawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 3), "点击 teaser 后应打开半屏笔记抽屉。")
        XCTAssertTrue(app.staticTexts["MeetingNotesDrawerGlyph"].exists, "抽屉 header 应展示笔记符号。")
        XCTAssertTrue(app.staticTexts["MeetingNotesDrawerTitle"].exists, "抽屉 header 应展示主标题。")
        XCTAssertFalse(app.staticTexts["MeetingNotesMergeHint"].exists, "抽屉里不应再展示辅助提示语。")

        let editor = app.textViews["MeetingNotesEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2), "笔记抽屉缺少输入框。")
        editor.tap()
        editor.typeText("temp note")

        let closeButton = app.buttons["MeetingNotesDrawerCloseButton"]
        XCTAssertTrue(closeButton.exists, "笔记抽屉缺少关闭按钮。")
        closeButton.tap()

        XCTAssertFalse(drawer.exists, "关闭后抽屉应消失。")

        teaser.tap()
        XCTAssertTrue(drawer.waitForExistence(timeout: 3), "再次点击 teaser 应能重新打开抽屉。")
        XCTAssertTrue(editor.waitForExistence(timeout: 2), "再次打开后输入框应仍存在。")
        let editorRetainsDraft = NSPredicate(format: "value CONTAINS %@", "temp note")
        expectation(for: editorRetainsDraft, evaluatedWith: editor)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testSummaryChatOpensUnifiedMinimalSheet() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let summaryTab = app.buttons["MeetingModeSummaryTab"]
        XCTAssertTrue(summaryTab.waitForExistence(timeout: 3), "详情页未正常打开。")
        summaryTab.tap()

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "AI Notes 页缺少与笔记对话入口。")
        askButton.tap()

        XCTAssertTrue(app.otherElements["MeetingChatSheet"].waitForExistence(timeout: 3), "点击与笔记对话后应打开统一的对话 sheet。")
        XCTAssertTrue(app.staticTexts["MeetingChatSheetGlyph"].exists, "对话 sheet header 应展示终端符号。")
        XCTAssertTrue(app.staticTexts["MeetingChatSheetTitle"].exists, "对话 sheet header 应展示主标题。")
        XCTAssertFalse(app.otherElements["SecondarySheetPanel"].exists, "对话 sheet 不应再使用旧的内层矩形面板。")
        XCTAssertFalse(app.otherElements["SecondarySheetHeaderBar"].exists, "对话 sheet 不应再使用旧的条纹标题栏。")
        XCTAssertTrue(app.textFields["MeetingChatComposerField"].waitForExistence(timeout: 2), "对话 sheet 缺少输入框。")
    }

    @MainActor
    func testMeetingChatSheetRemainsInteractiveAfterFocusingComposer() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let summaryTab = app.buttons["MeetingModeSummaryTab"]
        XCTAssertTrue(summaryTab.waitForExistence(timeout: 3), "详情页未正常打开。")
        summaryTab.tap()

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "AI Notes 页缺少与笔记对话入口。")
        askButton.tap()

        let chatSheet = app.otherElements["MeetingChatSheet"]
        XCTAssertTrue(chatSheet.waitForExistence(timeout: 3), "对话 sheet 未打开。")

        let composer = app.textFields["MeetingChatComposerField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2), "对话输入框缺失。")
        composer.tap()

        let closeButton = app.buttons["MeetingChatSheetCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2), "对话 sheet 缺少关闭按钮。")
        XCTAssertTrue(closeButton.isHittable, "聚焦输入框后关闭按钮不应失去交互。")
        closeButton.tap()

        XCTAssertFalse(chatSheet.waitForExistence(timeout: 2), "关闭按钮点击后，对话 sheet 应消失。")
    }

    @MainActor
    func testMeetingChatSheetWithHistoryRemainsInteractive() throws {
        let app = launchApp()

        let secondRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 1)
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5), "带历史对话的会议卡片未出现。")
        secondRow.tap()

        let summaryTab = app.buttons["MeetingModeSummaryTab"]
        XCTAssertTrue(summaryTab.waitForExistence(timeout: 3), "详情页未正常打开。")
        summaryTab.tap()

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "AI Notes 页缺少与笔记对话入口。")
        askButton.tap()

        let chatSheet = app.otherElements["MeetingChatSheet"]
        XCTAssertTrue(chatSheet.waitForExistence(timeout: 3), "对话 sheet 未打开。")

        let historicalSession = app.staticTexts["帮我总结用户最关心的问题"]
        XCTAssertTrue(historicalSession.waitForExistence(timeout: 3), "历史对话标题未显示。")

        let composer = app.textFields["MeetingChatComposerField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2), "对话输入框缺失。")
        composer.tap()

        let closeButton = app.buttons["MeetingChatSheetCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2), "对话 sheet 缺少关闭按钮。")
        XCTAssertTrue(closeButton.isHittable, "有历史对话时关闭按钮不应失去交互。")
        closeButton.tap()

        XCTAssertFalse(chatSheet.waitForExistence(timeout: 2), "关闭按钮点击后，对话 sheet 应消失。")
    }

    @MainActor
    func testMeetingChatShowsAssistantReplyAfterSending() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_IN_MEMORY")
        app.launchArguments.append("UITEST_USE_SIMULATOR_BACKEND")
        app.launch()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let summaryTab = app.buttons["MeetingModeSummaryTab"]
        XCTAssertTrue(summaryTab.waitForExistence(timeout: 3), "详情页未正常打开。")
        summaryTab.tap()

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "AI Notes 页缺少与笔记对话入口。")
        askButton.tap()

        let composer = app.textFields["MeetingChatComposerField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2), "对话输入框缺失。")
        composer.tap()
        composer.typeText("帮我总结")

        let sendButton = app.buttons.matching(identifier: "MeetingChatComposerSendButton").firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 2), "发送按钮缺少稳定的 accessibility identifier。")
        sendButton.tap()

        XCTAssertTrue(app.staticTexts["帮我总结"].waitForExistence(timeout: 5), "发送后用户消息未显示。")
        XCTAssertTrue(app.staticTexts["这是来自测试后端的回答。"].waitForExistence(timeout: 8), "发送后 AI 回答未显示。")
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

    private func edgeSwipeBack(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let finish = window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: finish)
    }
}
