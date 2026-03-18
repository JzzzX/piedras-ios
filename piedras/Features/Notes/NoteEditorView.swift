import SwiftUI

struct NoteEditorView: View {
    @Binding var text: String
    var showsHeader = true
    var title = "Notes"
    var placeholder = "Write here."
    var minHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedInk)

                    Text(title)
                        .font(AppTheme.editorialEmphasisFont(size: 20))
                        .foregroundStyle(AppTheme.ink)

                    Spacer()
                }
            }

            ZStack(alignment: .topLeading) {
                EditorialDocumentEditor(
                    text: $text,
                    placeholder: placeholder,
                    minHeight: minHeight,
                    fontSize: 17
                )
            }
        }
    }
}
