import SwiftUI

struct NoteEditorView: View {
    let meeting: Meeting
    let onNotesChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Personal notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Spacer()

                Text("Auto-saves")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            ZStack(alignment: .topLeading) {
                if meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write the moments that matter. AI notes will layer on top of this context.")
                        .font(.body)
                        .foregroundStyle(AppTheme.subtleInk)
                        .padding(.horizontal, 6)
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
                .frame(minHeight: 180)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
        }
    }
}
