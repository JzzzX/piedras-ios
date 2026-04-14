import Testing
import UIKit
@testable import CocoInterview

struct HomeRecordingDockButtonTests {
    @Test
    func idleDockButtonUsesMicrophoneNoteImageAsset() {
        #expect(HomeRecordingDockButton.idleAssetName == "HomeRecordingDockIdleIcon")
        #expect(UIImage(named: HomeRecordingDockButton.idleAssetName) != nil)
    }
}
