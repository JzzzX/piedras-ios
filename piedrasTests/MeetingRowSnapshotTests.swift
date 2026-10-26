import Foundation
import Testing
@testable import piedras

struct MeetingRowSnapshotTests {
    @Test
    func processingSnapshotUsesProcessingBadgeInsteadOfRecordingBadge() {
        let meeting = Meeting(
            title: "停止后的会议",
            date: .now,
            status: .ended
        )

        let snapshot = MeetingRowSnapshot(
            meeting: meeting,
            isRecording: false,
            isProcessing: true
        )

        #expect(snapshot.isRecording == false)
        #expect(snapshot.isProcessing == true)
        #expect(snapshot.showsSyncFailure == false)
    }
}
