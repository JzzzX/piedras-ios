import SwiftUI
import UIKit

enum EditorialDocumentEditorStyle {
    case editorial
    case body
}

struct EditorialDocumentEditor: View {
    @Binding var text: String

    var placeholder: String
    var minHeight: CGFloat = 320
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = AppTheme.editorialBodyLineSpacing
    var style: EditorialDocumentEditorStyle = .editorial
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var usesSmartDashes = true
    var usesSmartQuotes = true
    var accessibilityIdentifier: String? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(swiftUIFont)
                    .foregroundStyle(AppTheme.subtleInk)
                    .allowsHitTesting(false)
                    .padding(.top, 2)
            }

            EditorialTextView(
                text: $text,
                font: uiFont,
                textColor: UIColor(AppTheme.ink),
                tintColor: UIColor(AppTheme.accent),
                lineSpacing: lineSpacing,
                autocapitalization: autocapitalization,
                usesSmartDashes: usesSmartDashes,
                usesSmartQuotes: usesSmartQuotes,
                accessibilityIdentifier: accessibilityIdentifier
            )
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
    }

    private var swiftUIFont: Font {
        switch style {
        case .editorial:
            return AppTheme.editorialFont(size: fontSize)
        case .body:
            return AppTheme.bodyFont(size: fontSize)
        }
    }

    private var uiFont: UIFont {
        switch style {
        case .editorial:
            return AppTheme.editorialUIFont(size: fontSize, weight: .regular)
        case .body:
            return AppTheme.bodyUIFont(size: fontSize, weight: .regular)
        }
    }
}

private struct EditorialTextView: UIViewRepresentable {
    @Binding var text: String

    let font: UIFont
    let textColor: UIColor
    let tintColor: UIColor
    let lineSpacing: CGFloat
    let autocapitalization: UITextAutocapitalizationType
    let usesSmartDashes: Bool
    let usesSmartQuotes: Bool
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.keyboardDismissMode = .interactive
        textView.adjustsFontForContentSizeCategory = false
        textView.autocapitalizationType = autocapitalization
        textView.smartDashesType = usesSmartDashes ? .yes : .no
        textView.smartQuotesType = usesSmartQuotes ? .yes : .no
        textView.tintColor = tintColor
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityValue = text
        applyStyle(to: textView, text: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.tintColor = tintColor
        textView.autocapitalizationType = autocapitalization
        textView.smartDashesType = usesSmartDashes ? .yes : .no
        textView.smartQuotesType = usesSmartQuotes ? .yes : .no
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityValue = text

        guard textView.text != text || textView.font != font else {
            textView.typingAttributes = typingAttributes
            return
        }

        let selectedRange = textView.selectedRange
        applyStyle(to: textView, text: text)
        let safeLocation = min(selectedRange.location, textView.attributedText.length)
        textView.selectedRange = NSRange(location: safeLocation, length: 0)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 0, 1)
        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fittedSize = uiView.sizeThatFits(targetSize)
        return CGSize(width: width, height: max(fittedSize.height, 1))
    }

    private func applyStyle(to textView: UITextView, text: String) {
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: typingAttributes
        )
        textView.typingAttributes = typingAttributes
        textView.accessibilityValue = text
    }

    private var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
