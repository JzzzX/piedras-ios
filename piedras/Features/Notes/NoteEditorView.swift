import SwiftUI

struct NoteEditorView: View {
    let meeting: Meeting
    var showsHeader = true
    let onNotesChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedInk)

                    Text("Notes")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Spacer()
                }
            }

            ZStack(alignment: .topLeading) {
                if meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write anything worth keeping.")
                        .font(.body)
                        .foregroundStyle(AppTheme.subtleInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
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
                .frame(minHeight: 220)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background {
                PaperSurface(
                    cornerRadius: 24,
                    fill: AppTheme.documentPaper,
                    border: AppTheme.documentHairline,
                    shadowOpacity: 0.04
                )
            }
        }
    }
}
