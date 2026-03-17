import SwiftUI

struct NoteEditorView: View {
    let meeting: Meeting
    let onNotesChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)

                Text("Notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a few lines.")
                        .font(.body)
                        .foregroundStyle(AppTheme.subtleInk)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(
                    text: Binding(
                        get: { meeting.userNotesPlainText },
                        set: { onNotesChange($0) }
                    )
                )
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
            }
        }
    }
}
