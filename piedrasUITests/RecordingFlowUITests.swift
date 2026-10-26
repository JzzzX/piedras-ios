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
    func testHomeDockUsesTwoSlotLayoutAndBrandOnlyTitle() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["NewRecordingButton"].waitForExistence(timeout: 5), "首页录音入口未出现。")
        XCTAssertTrue(app.buttons["HomeGlobalChatLauncher"].waitForExistence(timeout: 5), "首页对话入口未出现。")
        XCTAssertTrue(app.buttons["HomeFolderButton"].waitForExistence(timeout: 5), "首页顶部缺少文件夹入口。")
        XCTAssertTrue(app.buttons["HomeSearchButton"].exists, "首页顶部缺少搜索入口。")
        XCTAssertTrue(app.buttons["HomeSettingsButton"].exists, "首页顶部缺少设置入口。")

        XCTAssertTrue(app.staticTexts["Piedras"].waitForExistence(timeout: 5), "首页品牌标题未出现。")
        XCTAssertFalse(app.staticTexts["Piedras 笔记"].exists, "首页标题应简化为 Piedras。")
        XCTAssertFalse(app.buttons["HomeNotesButton"].exists, "dock 应回退为两格结构，不再展示左侧笔记入口。")
        XCTAssertTrue(app.staticTexts["与笔记对话"].exists, "dock 右侧应恢复文字对话入口。")
    }

    @MainActor
    func testHomeFolderButtonOpensDrawerAndHidesBottomDock() throws {
        let app = launchApp()

        let folderButton = app.buttons["HomeFolderButton"]
        XCTAssertTrue(folderButton.waitForExistence(timeout: 5), "首页顶部缺少文件夹入口。")
        folderButton.tap()

        let newFolderButton = app.buttons["FolderDrawerNewFolderButton"]
        XCTAssertTrue(newFolderButton.waitForExistence(timeout: 3), "点击文件夹入口后应打开左侧抽屉。")
        XCTAssertFalse(app.buttons["NewRecordingButton"].exists, "打开文件夹抽屉时不应继续展示底部录音入口。")
        XCTAssertFalse(app.buttons["HomeGlobalChatLauncher"].exists, "打开文件夹抽屉时不应继续展示底部对话入口。")

        app.buttons["FolderDrawerCloseButton"].tap()

        XCTAssertFalse(newFolderButton.exists, "关闭后文件夹抽屉应消失。")
        XCTAssertTrue(app.buttons["NewRecordingButton"].waitForExistence(timeout: 3), "关闭抽屉后应恢复底部录音入口。")
        XCTAssertTrue(app.buttons["HomeGlobalChatLauncher"].waitForExistence(timeout: 3), "关闭抽屉后应恢复底部对话入口。")
    }

    @MainActor
    func testFolderDrawerKeepsSystemFoldersPinnedWithoutDeleteAction() throws {
        let app = launchApp()

        let folderButton = app.buttons["HomeFolderButton"]
        XCTAssertTrue(folderButton.waitForExistence(timeout: 5), "首页顶部缺少文件夹入口。")
        folderButton.tap()

        let defaultFolderRow = app.buttons["FolderDrawerRow_preview-notes"]
        XCTAssertTrue(defaultFolderRow.waitForExistence(timeout: 3), "默认文件夹应常驻展示。")

        let recentlyDeletedRow = app.buttons["FolderDrawerRow_preview-recently-deleted"]
        XCTAssertTrue(recentlyDeletedRow.waitForExistence(timeout: 3), "最近删除文件夹应常驻展示。")

        XCTAssertFalse(app.buttons["FolderDrawerDeleteButton_preview-notes"].exists, "默认文件夹不应出现删除按钮。")
        XCTAssertFalse(
            app.buttons["FolderDrawerDeleteButton_preview-recently-deleted"].exists,
            "最近删除文件夹不应出现删除按钮。"
        )
    }

    @MainActor
    func testMeetingRowSupportsSwipeToDelete() throws {
        let app = launchApp()
        let seededTitle = "Piedras iOS MVP Kickoff"

        let rows = app.descendants(matching: .any).matching(identifier: "MeetingRow")
        let firstRow = rows.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.swipeLeft()

        let deleteButton = app.buttons["MeetingRowDeleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "左滑后自定义垃圾桶按钮未出现。")
        XCTAssertFalse(app.buttons["删除"].exists, "不应再展示系统原生删除文案按钮。")
        deleteButton.tap()

        let deletedTitle = app.staticTexts[seededTitle]
        let predicate = NSPredicate(format: "exists == false")
        expectation(for: predicate, evaluatedWith: deletedTitle)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.otherElements["HomeErrorBanner"].exists, "本地删除成功后不应再展示错误横幅。")
    }

    @MainActor
    func testMeetingListStillScrollsVerticallyAfterHorizontalSwipeAttempt() throws {
        let app = launchApp()

        let rows = app.descendants(matching: .any).matching(identifier: "MeetingRow")
        let firstRow = rows.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.swipeLeft()

        let deleteButton = app.buttons["MeetingRowDeleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "左滑后自定义按钮未出现。")

        let distantTitle = app.staticTexts["Preview Archive 7"]
        XCTAssertFalse(distantTitle.exists, "测试前置条件错误：远端条目不应一开始就出现在首屏。")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 2), "首页窗口未出现。")

        window.swipeUp()
        window.swipeUp()
        window.swipeUp()

        XCTAssertTrue(distantTitle.waitForExistence(timeout: 3), "横滑后首页列表仍应可以继续纵向滚动。")
    }

    @MainActor
    func testMeetingRowMoveActionMovesMeetingIntoSelectedFolder() throws {
        let app = launchApp()
        let folderName = "项目归档"
        let seededTitle = "Piedras iOS MVP Kickoff"

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.swipeLeft()

        let moveButton = app.buttons["MeetingRowMoveButton"]
        XCTAssertTrue(moveButton.waitForExistence(timeout: 3), "左滑后移动按钮未出现。")
        moveButton.tap()

        let targetFolderButton = app.buttons[folderName]
        XCTAssertTrue(targetFolderButton.waitForExistence(timeout: 3), "移动面板未展示目标文件夹。")
        targetFolderButton.tap()

        let movedOutPredicate = NSPredicate(format: "exists == false")
        expectation(for: movedOutPredicate, evaluatedWith: app.staticTexts[seededTitle])
        waitForExpectations(timeout: 3)

        let folderButton = app.buttons["HomeFolderButton"]
        XCTAssertTrue(folderButton.waitForExistence(timeout: 3), "首页顶部缺少文件夹入口。")
        folderButton.tap()
        XCTAssertTrue(app.buttons[folderName].waitForExistence(timeout: 3), "抽屉里应展示目标文件夹。")
        app.buttons[folderName].tap()

        XCTAssertTrue(app.staticTexts[seededTitle].waitForExistence(timeout: 3), "移动后应能在目标文件夹里看到这条 note。")
    }

    @MainActor
    func testMeetingDetailSupportsEdgeSwipeBack() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let detailTitle = app.buttons["MeetingDetailTitleButton"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 3), "详情页未正常打开。")

        edgeSwipeBack(in: app)

        let homeLauncher = app.buttons["HomeGlobalChatLauncher"]
        XCTAssertTrue(homeLauncher.waitForExistence(timeout: 5), "右滑返回后应回到首页。")
        XCTAssertFalse(detailTitle.exists, "右滑返回后不应仍停留在详情页。")
    }

    @MainActor
    func testMeetingDetailMenuShowsImmersiveActions() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        XCTAssertFalse(app.staticTexts["Piedras AI"].exists, "详情页不应再展示品牌标题。")
        XCTAssertTrue(app.buttons["MeetingTranscriptSheetButton"].waitForExistence(timeout: 3), "缺少 Transcript 入口。")
        XCTAssertTrue(app.buttons["MeetingAskButton"].exists, "详情页缺少 Chat with note 入口。")
        XCTAssertTrue(app.buttons["MeetingTranscriptNotesTeaser"].exists, "详情页缺少笔记抽屉入口。")
        XCTAssertTrue(app.otherElements["EnhancedNotesRenderedView"].waitForExistence(timeout: 3), "AI Notes 应默认展示渲染后的文稿。")
        XCTAssertFalse(app.staticTexts["## 会议摘要"].exists, "AI Notes 默认页不应暴露原始 markdown 标记。")

        app.buttons["MeetingTranscriptSheetButton"].tap()
        XCTAssertTrue(app.otherElements["MeetingTranscriptSheet"].waitForExistence(timeout: 3), "点击 Transcript 后应打开 transcript sheet。")
        XCTAssertTrue(app.staticTexts["MeetingTranscriptSheetTitle"].exists, "Transcript sheet 缺少标题。")
        XCTAssertTrue(element(in: app, identifier: "TranscriptTimestamp").waitForExistence(timeout: 3), "Transcript sheet 缺少时间戳。")
        XCTAssertTrue(app.otherElements.matching(identifier: "TranscriptSpeakerAvatar").firstMatch.exists, "Transcript sheet 缺少说话人头像。")
        XCTAssertTrue(app.buttons.matching(identifier: "TranscriptSpeakerHeaderButton").firstMatch.exists, "Transcript sheet 缺少说话人标题入口。")
        XCTAssertTrue(app.otherElements.matching(identifier: "TranscriptSegmentDivider").firstMatch.exists, "Transcript sheet 缺少段落分隔线。")

        let speakerHeader = app.buttons.matching(identifier: "TranscriptSpeakerHeaderButton").firstMatch
        speakerHeader.tap()
        let renameAlert = app.alerts["重命名说话人"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 2), "点击说话人标题后应打开重命名弹窗。")
        renameAlert.buttons["取消"].tap()
        app.buttons["MeetingTranscriptSheetCloseButton"].tap()

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
    func testMeetingTypeSelectorOpensCustomOverlay() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let selector = app.buttons["MeetingTypeMenu"]
        XCTAssertTrue(selector.waitForExistence(timeout: 3), "会议类型入口未出现。")
        selector.tap()

        XCTAssertTrue(app.otherElements["MeetingTypeOverlay"].waitForExistence(timeout: 2), "点击会议类型后应出现自定义浮层。")
        XCTAssertTrue(app.buttons["MeetingTypeOption_访谈"].exists, "浮层中应展示可选会议类型。")
    }

    @MainActor
    func testMeetingDetailMenuDismissesWithoutTriggeringUnderlyingAction() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

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

        let teaser = app.buttons["MeetingTranscriptNotesTeaser"]
        XCTAssertTrue(teaser.waitForExistence(timeout: 3), "详情页应显示我的笔记预览入口。")
        XCTAssertTrue(element(in: app, identifier: "MeetingTranscriptNotesTeaserGlyph").exists, "我的笔记入口应展示简易符号。")
        teaser.tap()

        let drawer = app.otherElements["MeetingNotesDrawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 3), "点击 teaser 后应打开半屏笔记抽屉。")
        XCTAssertTrue(element(in: app, identifier: "MeetingNotesDrawerGlyph").exists, "抽屉 header 应展示笔记符号。")
        XCTAssertTrue(element(in: app, identifier: "MeetingNotesDrawerTitle").exists, "抽屉 header 应展示主标题。")
        XCTAssertFalse(app.staticTexts["MeetingNotesMergeHint"].exists, "抽屉里不应再展示辅助提示语。")
        XCTAssertTrue(
            element(in: app, identifier: "MeetingNoteAttachmentsSection", fallbackLabel: "资料区").exists,
            "抽屉默认应直接展示资料区。"
        )
        XCTAssertTrue(
            element(in: app, identifier: "MeetingNoteAttachmentsCameraButton", fallbackLabel: "拍照").exists,
            "资料区应直接展示拍照入口。"
        )
        XCTAssertTrue(
            element(in: app, identifier: "MeetingNoteAttachmentsPhotoButton", fallbackLabel: "添加图片").exists,
            "资料区应直接展示图片导入入口。"
        )

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
    func testNotesDrawerCameraActionKeepsDrawerContext() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_IN_MEMORY")
        app.launchArguments.append("UITEST_DISABLE_CAMERA")
        app.launch()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let teaser = app.buttons["MeetingTranscriptNotesTeaser"]
        XCTAssertTrue(teaser.waitForExistence(timeout: 3), "详情页应显示我的笔记预览入口。")
        teaser.tap()

        let drawer = app.otherElements["MeetingNotesDrawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 3), "点击 teaser 后应打开半屏笔记抽屉。")

        let cameraButton = element(
            in: app,
            identifier: "MeetingNoteAttachmentsCameraButton",
            fallbackLabel: "拍照"
        )
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 2), "资料区缺少拍照入口。")
        cameraButton.tap()

        XCTAssertTrue(drawer.waitForExistence(timeout: 2), "触发拍照后，笔记抽屉不应丢失当前上下文。")
    }

    @MainActor
    func testSummaryChatOpensUnifiedMinimalSheet() throws {
        let app = launchApp()

        let firstRow = app.descendants(matching: .any).matching(identifier: "MeetingRow").element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "首页会议卡片未出现。")
        firstRow.tap()

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "详情页缺少与笔记对话入口。")
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

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "详情页缺少与笔记对话入口。")
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

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "详情页缺少与笔记对话入口。")
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

        let askButton = app.buttons["MeetingAskButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 3), "详情页缺少与笔记对话入口。")
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
        let candidateLabels = [
            "允许",
            "好",
            "OK",
            "Allow",
            "Allow While Using App",
        ]
        let alertHosts = [
            app,
            XCUIApplication(bundleIdentifier: "com.apple.springboard"),
        ]

        for host in alertHosts {
            for label in candidateLabels {
                let button = host.buttons[label]
                if button.waitForExistence(timeout: 0.5) {
                    button.tap()
                    return
                }
            }

            let alert = host.alerts.firstMatch
            if alert.waitForExistence(timeout: 0.5),
               alert.buttons.firstMatch.exists {
                alert.buttons.firstMatch.tap()
                return
            }
        }
    }

    private func edgeSwipeBack(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let finish = window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: finish)
    }
}

final class RecordingDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordingDetailShowsFocusedNotePromptAndInlineTitleEdit() throws {
        let app = launchApp()

        let newRecordingButton = element(in: app, identifier: "NewRecordingButton", fallbackLabel: "新录音")
        XCTAssertTrue(newRecordingButton.waitForExistence(timeout: 8), "首页录音入口未出现。")
        newRecordingButton.tap()

        dismissPermissionAlertsIfNeeded(in: app)

        XCTAssertTrue(waitForRecordingDetail(in: app), "开始录音后未进入录音态。")

        let titleEditButton = app.buttons["RecordingDetailTitleEditButton"]
        XCTAssertTrue(titleEditButton.waitForExistence(timeout: 3), "录音态标题区应显示直接编辑按钮。")

        XCTAssertFalse(app.staticTexts["RecordingDetailSecondaryRecBadge"].exists, "正文标题下不应再显示第二个 REC 标识。")

        let editor = app.textViews["RecordingNoteEditor"]
        let notePrompt = app.buttons["RecordingDetailNotePrompt"]
        if notePrompt.waitForExistence(timeout: 2) {
            notePrompt.tap()
        } else {
            XCTAssertTrue(editor.waitForExistence(timeout: 2), "录音正文编辑器缺失。")
            editor.tap()
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 2), "录音正文编辑器缺失。")
        editor.tap()

        editor.typeText("abc")

        let editorContainsTypedText = NSPredicate(format: "value CONTAINS %@", "abc")
        expectation(for: editorContainsTypedText, evaluatedWith: editor)
        waitForExpectations(timeout: 3)

        let stopButton = element(in: app, identifier: "StopRecordingButton", fallbackLabel: "停止录音")
        if stopButton.waitForExistence(timeout: 3) {
            stopButton.tap()
        }
    }

    @MainActor
    func testRecordingDetailShowsKeyboardDismissActionWhileEditing() throws {
        let app = launchApp()

        let newRecordingButton = element(in: app, identifier: "NewRecordingButton", fallbackLabel: "新录音")
        XCTAssertTrue(newRecordingButton.waitForExistence(timeout: 8), "首页录音入口未出现。")
        newRecordingButton.tap()

        dismissPermissionAlertsIfNeeded(in: app)

        XCTAssertTrue(waitForRecordingDetail(in: app), "开始录音后未进入录音态。")

        XCTAssertTrue(app.staticTexts["笔记类型"].waitForExistence(timeout: 3), "录音态应展示“笔记类型”文案。")

        let editor = app.textViews["RecordingNoteEditor"]
        let notePrompt = app.buttons["RecordingDetailNotePrompt"]
        if notePrompt.waitForExistence(timeout: 2) {
            notePrompt.tap()
        } else {
            XCTAssertTrue(editor.waitForExistence(timeout: 2), "录音正文编辑器缺失。")
            editor.tap()
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 2), "录音正文编辑器缺失。")
        editor.tap()
        editor.typeText("abc")

        let dismissButton = element(
            in: app,
            identifier: "RecordingBottomBarDismissKeyboardButton",
            fallbackLabel: "收起键盘"
        )
        let stopButton = element(
            in: app,
            identifier: "StopRecordingButton",
            fallbackLabel: "停止录音"
        )
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 2), "进入输入态后底栏右侧应切换为收起键盘入口。")
        XCTAssertFalse(stopButton.isHittable, "进入输入态后底栏右侧不应继续显示结束录音按钮。")
        XCTAssertTrue(element(in: app, identifier: "RecordingDetailCompactHeader").waitForExistence(timeout: 2), "进入输入态后应切换为紧凑标题摘要。")
        XCTAssertFalse(app.buttons["RecordingDetailTitleEditButton"].exists, "进入输入态后不应继续展示标题编辑按钮。")
        XCTAssertFalse(app.staticTexts["笔记类型"].exists, "进入输入态后应折叠笔记类型区域。")
        XCTAssertFalse(app.buttons["RecordingBottomBarTranscriptTrigger"].exists, "进入输入态后底栏不应继续展示转写预览行。")

        dismissButton.tap()

        XCTAssertTrue(stopButton.waitForExistence(timeout: 2), "收起键盘后底栏右侧应恢复结束录音按钮。")
        XCTAssertTrue(stopButton.isHittable, "收起键盘后应可再次直接结束录音。")
        stopButton.tap()
    }

    @MainActor
    func testRecordingDetailKeepsEditorReachableWithCompactAttachmentStrip() throws {
        let app = launchApp(extraArguments: ["UITEST_RECORDING_SEED_ATTACHMENT"])

        let newRecordingButton = element(in: app, identifier: "NewRecordingButton", fallbackLabel: "新录音")
        XCTAssertTrue(newRecordingButton.waitForExistence(timeout: 8), "首页录音入口未出现。")
        newRecordingButton.tap()

        dismissPermissionAlertsIfNeeded(in: app)

        let editor = app.textViews["RecordingNoteEditor"]
        let notePrompt = app.buttons["RecordingDetailNotePrompt"]
        if notePrompt.waitForExistence(timeout: 2) {
            notePrompt.tap()
        } else {
            XCTAssertTrue(editor.waitForExistence(timeout: 2), "录音正文编辑器缺失。")
            editor.tap()
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 2), "录音正文编辑器缺失。")
        editor.tap()
        editor.typeText("attachment check")

        let compactStrip = element(
            in: app,
            identifier: "RecordingAttachmentCompactStrip",
            fallbackLabel: "资料区"
        )
        XCTAssertTrue(compactStrip.waitForExistence(timeout: 2), "进入输入态后应保留紧凑附件条。")

        let dismissButton = element(
            in: app,
            identifier: "RecordingBottomBarDismissKeyboardButton",
            fallbackLabel: "收起键盘"
        )
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 2), "进入输入态后应显示收起键盘入口。")
        XCTAssertTrue(element(in: app, identifier: "RecordingDetailCompactHeader").waitForExistence(timeout: 2), "进入输入态后应保留紧凑标题摘要。")
        XCTAssertFalse(app.staticTexts["笔记类型"].exists, "进入输入态后应折叠笔记类型区域。")
        XCTAssertFalse(app.buttons["RecordingBottomBarTranscriptTrigger"].exists, "进入输入态后底栏不应继续展示转写预览行。")
        XCTAssertTrue(editor.isHittable, "有附件时进入输入态后，正文编辑器仍应处于可见可点击状态。")
        XCTAssertLessThan(editor.frame.minY, compactStrip.frame.minY, "正文编辑器应位于紧凑附件条上方可见区域。")
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_IN_MEMORY")
        app.launchArguments.append(contentsOf: extraArguments)
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

    private func waitForRecordingDetail(in app: XCUIApplication, timeout: TimeInterval = 12) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let titleEditButton = app.buttons["RecordingDetailTitleEditButton"]
        let notePrompt = app.buttons["RecordingDetailNotePrompt"]
        let editor = app.textViews["RecordingNoteEditor"]
        let recBadge = app.staticTexts["RecBadge"]

        repeat {
            if titleEditButton.exists || notePrompt.exists || editor.exists || recBadge.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return titleEditButton.exists || notePrompt.exists || editor.exists || recBadge.exists
    }

    private func dismissPermissionAlertsIfNeeded(in app: XCUIApplication) {
        let candidateLabels = [
            "允许",
            "好",
            "OK",
            "Allow",
            "Allow While Using App",
        ]
        let alertHosts = [
            app,
            XCUIApplication(bundleIdentifier: "com.apple.springboard"),
        ]

        for host in alertHosts {
            for label in candidateLabels {
                let button = host.buttons[label]
                if button.waitForExistence(timeout: 0.5) {
                    button.tap()
                    return
                }
            }

            let alert = host.alerts.firstMatch
            if alert.waitForExistence(timeout: 0.5),
               alert.buttons.firstMatch.exists {
                alert.buttons.firstMatch.tap()
                return
            }
        }
    }
}
