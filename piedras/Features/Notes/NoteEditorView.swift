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
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(AppTheme.editorialFont(size: 19))
                        .foregroundStyle(AppTheme.subtleInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(AppTheme.editorialFont(size: 19))
                    .foregroundStyle(AppTheme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(.horizontal, -5)
                    .padding(.vertical, -8)
            }
        }
    }
}
