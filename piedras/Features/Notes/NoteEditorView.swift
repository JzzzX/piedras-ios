import SwiftUI

struct NoteEditorView: View {
    let meeting: Meeting
    let onNotesChange: (String) -> Void

    var body: some View {
        TextEditor(
            text: Binding(
                get: { meeting.userNotesPlainText },
                set: { onNotesChange($0) }
            )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
