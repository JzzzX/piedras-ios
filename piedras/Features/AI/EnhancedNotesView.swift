import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore

    let text: String

    let meetingID: String

    var body: some View {
        MarkdownDocumentView(
            markdown: text,
            placeholder: meetingStore.isEnhancing(meetingID: meetingID) ? "Generating notes..." : "No AI notes yet.",
            minHeight: 420,
            accessibilityIdentifier: "EnhancedNotesRenderedView"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
