import SwiftUI

struct NoteEditorView: View {
    @Binding var text: String
    var showsHeader = true
    var title = "Notes"
    var placeholder = "Write here."
    var minHeight: CGFloat = 260
    var usesBodyStyle = false
    var focusRequestToken: Int = 0
    var isFocused: Binding<Bool>? = nil
    var accessibilityIdentifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedInk)

                    Text(title)
                        .font(usesBodyStyle ? AppTheme.bodyFont(size: 20, weight: .bold) : AppTheme.editorialEmphasisFont(size: 20))
                        .foregroundStyle(AppTheme.ink)

                    Spacer()
                }
            }

            ZStack(alignment: .topLeading) {
                EditorialDocumentEditor(
                    text: $text,
                    placeholder: placeholder,
                    minHeight: minHeight,
                    fontSize: 17,
                    style: usesBodyStyle ? .body : .editorial,
                    focusRequestToken: focusRequestToken,
                    isFocused: isFocused,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            }
        }
    }
}
