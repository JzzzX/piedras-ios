import CoreGraphics
import Testing
@testable import piedras

struct NavigationInteractionChromeTests {
    @Test
    func pushedMeetingDetailReliesOnSystemInteractivePop() {
        #expect(MeetingDetailDismissGestureMode.forPushDestination.usesCustomEdgeSwipe == false)
    }

    @Test
    func sheetMeetingDetailFlowsKeepCustomEdgeSwipeDismiss() {
        #expect(MeetingDetailDismissGestureMode.forSheet.usesCustomEdgeSwipe)
    }

    @Test
    func closedFolderDrawerLivesFullyOffscreenAndDisablesInteractions() {
        let chrome = FolderDrawerPresentationChrome(isPresented: false, drawerWidth: 280)

        #expect(chrome.panelOffset == -280)
        #expect(chrome.backdropOpacity == 0)
        #expect(chrome.allowsHitTesting == false)
        #expect(chrome.hidesAccessibility)
    }

    @Test
    func openFolderDrawerPinsPanelAndEnablesBackdropInteractions() {
        let chrome = FolderDrawerPresentationChrome(isPresented: true, drawerWidth: 280)

        #expect(chrome.panelOffset == 0)
        #expect(chrome.backdropOpacity == 0.34)
        #expect(chrome.allowsHitTesting)
        #expect(chrome.hidesAccessibility == false)
    }
}
