import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore

    @Binding var text: String

    let meetingID: String

    var body: some View {
        EditorialDocumentEditor(
            text: $text,
            placeholder: meetingStore.isEnhancing(meetingID: meetingID) ? "Generating notes..." : "Write here.",
            minHeight: 420,
            fontSize: 17,
            lineSpacing: AppTheme.editorialBodyLineSpacing,
            accessibilityIdentifier: "EnhancedNotesEditor"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
