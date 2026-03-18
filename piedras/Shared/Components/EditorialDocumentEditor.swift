import SwiftUI
import UIKit

struct EditorialDocumentEditor: View {
    @Binding var text: String

    var placeholder: String
    var minHeight: CGFloat = 320
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = AppTheme.editorialBodyLineSpacing
    var accessibilityIdentifier: String? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(AppTheme.editorialFont(size: fontSize))
                    .foregroundStyle(AppTheme.subtleInk)
                    .allowsHitTesting(false)
                    .padding(.top, 2)
            }

            EditorialTextView(
                text: $text,
                font: AppTheme.editorialUIFont(size: fontSize, weight: .regular),
                textColor: UIColor(AppTheme.ink),
                tintColor: UIColor(AppTheme.accent),
                lineSpacing: lineSpacing,
                accessibilityIdentifier: accessibilityIdentifier
            )
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
    }
}

private struct EditorialTextView: UIViewRepresentable {
    @Binding var text: String

    let font: UIFont
    let textColor: UIColor
    let tintColor: UIColor
    let lineSpacing: CGFloat
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
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.tintColor = tintColor
        textView.accessibilityIdentifier = accessibilityIdentifier
        applyStyle(to: textView, text: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.tintColor = tintColor
        textView.accessibilityIdentifier = accessibilityIdentifier

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
