import SwiftUI
import UIKit

enum EditorialDocumentEditorStyle {
    case editorial
    case body
}

enum EditorialCaretScrollBehavior: Equatable {
    case visibleOnly
    case pinCurrentLineNearTop(topPadding: CGFloat)
}

enum EditorialPinnedCaretMetrics {
    static func targetContentOffsetY(
        currentOffsetY: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        insetTop: CGFloat,
        insetBottom: CGFloat,
        caretRect: CGRect,
        topPadding: CGFloat
    ) -> CGFloat? {
        guard viewportHeight > 0 else { return nil }
        guard !caretRect.isNull, !caretRect.isInfinite else { return nil }

        let visibleTop = currentOffsetY + insetTop
        let visibleBottom = currentOffsetY + viewportHeight - insetBottom
        let minOffsetY = -insetTop
        let maxOffsetY = max(minOffsetY, contentHeight - viewportHeight + insetBottom)
        let desiredOffsetY = min(
            max(caretRect.minY - insetTop - topPadding, minOffsetY),
            maxOffsetY
        )

        if caretRect.minY < visibleTop || caretRect.maxY > visibleBottom {
            return abs(desiredOffsetY - currentOffsetY) > 0.5 ? desiredOffsetY : nil
        }

        return nil
    }
}

struct EditorialDocumentEditor: View {
    @Binding var text: String

    var placeholder: String
    var minHeight: CGFloat = 320
    var fixedHeight: CGFloat? = nil
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = AppTheme.editorialBodyLineSpacing
    var style: EditorialDocumentEditorStyle = .editorial
    var allowsInternalScrolling = false
    var dismissKeyboardAccessoryLabel: String? = nil
    var hidesAccessibility = false
    var allowsDirectEditing = true
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var usesSmartDashes = true
    var usesSmartQuotes = true
    var focusRequestToken: Int = 0
    var isFocused: Binding<Bool>? = nil
    var accessibilityIdentifier: String? = nil
    var caretScrollBehavior: EditorialCaretScrollBehavior = .visibleOnly

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
                allowsInternalScrolling: allowsInternalScrolling,
                layoutHeightFallback: fixedHeight ?? minHeight,
                dismissKeyboardAccessoryLabel: dismissKeyboardAccessoryLabel,
                hidesAccessibility: hidesAccessibility,
                allowsDirectEditing: allowsDirectEditing,
                autocapitalization: autocapitalization,
                usesSmartDashes: usesSmartDashes,
                usesSmartQuotes: usesSmartQuotes,
                focusRequestToken: focusRequestToken,
                isFocused: isFocused,
                accessibilityIdentifier: accessibilityIdentifier,
                caretScrollBehavior: caretScrollBehavior
            )
        }
        .frame(
            minHeight: fixedHeight == nil ? minHeight : nil,
            maxHeight: fixedHeight,
            alignment: .topLeading
        )
        .frame(height: fixedHeight, alignment: .topLeading)
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
    let allowsInternalScrolling: Bool
    let layoutHeightFallback: CGFloat
    let dismissKeyboardAccessoryLabel: String?
    let hidesAccessibility: Bool
    let allowsDirectEditing: Bool
    let autocapitalization: UITextAutocapitalizationType
    let usesSmartDashes: Bool
    let usesSmartQuotes: Bool
    let focusRequestToken: Int
    let isFocused: Binding<Bool>?
    let accessibilityIdentifier: String?
    let caretScrollBehavior: EditorialCaretScrollBehavior

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: isFocused,
            lastFocusRequestToken: focusRequestToken,
            caretScrollBehavior: caretScrollBehavior
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.backgroundColor = .clear
        textView.isScrollEnabled = allowsInternalScrolling
        textView.showsVerticalScrollIndicator = allowsInternalScrolling
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.keyboardDismissMode = .interactive
        textView.adjustsFontForContentSizeCategory = false
        textView.isEditable = allowsDirectEditing
        textView.isSelectable = allowsDirectEditing
        textView.autocapitalizationType = autocapitalization
        textView.smartDashesType = usesSmartDashes ? .yes : .no
        textView.smartQuotesType = usesSmartQuotes ? .yes : .no
        textView.tintColor = tintColor
        textView.inputAccessoryView = context.coordinator.makeInputAccessoryView(
            label: dismissKeyboardAccessoryLabel,
            tintColor: tintColor
        )
        textView.isAccessibilityElement = !hidesAccessibility
        textView.accessibilityElementsHidden = hidesAccessibility
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityValue = text
        applyStyle(to: textView, text: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.tintColor = tintColor
        context.coordinator.textView = textView
        textView.isScrollEnabled = allowsInternalScrolling
        textView.showsVerticalScrollIndicator = allowsInternalScrolling
        textView.isEditable = allowsDirectEditing
        textView.isSelectable = allowsDirectEditing
        textView.autocapitalizationType = autocapitalization
        textView.smartDashesType = usesSmartDashes ? .yes : .no
        textView.smartQuotesType = usesSmartQuotes ? .yes : .no
        textView.inputAccessoryView = context.coordinator.makeInputAccessoryView(
            label: dismissKeyboardAccessoryLabel,
            tintColor: tintColor
        )
        textView.isAccessibilityElement = !hidesAccessibility
        textView.accessibilityElementsHidden = hidesAccessibility
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityValue = text
        context.coordinator.isFocused = isFocused
        context.coordinator.caretScrollBehavior = caretScrollBehavior

        if context.coordinator.lastFocusRequestToken != focusRequestToken {
            context.coordinator.lastFocusRequestToken = focusRequestToken
            if !textView.isFirstResponder {
                DispatchQueue.main.async {
                    textView.becomeFirstResponder()
                }
            }
        }

        guard textView.text != text || textView.font != font else {
            textView.typingAttributes = typingAttributes
            return
        }

        let selectedRange = textView.selectedRange
        applyStyle(to: textView, text: text)
        let safeLocation = min(selectedRange.location, textView.attributedText.length)
        textView.selectedRange = NSRange(location: safeLocation, length: 0)
        context.coordinator.scrollSelectionIntoViewIfNeeded(textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 0, 1)
        if allowsInternalScrolling {
            let height = max(proposal.height ?? layoutHeightFallback, 1)
            return CGSize(width: width, height: height)
        }

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
        var isFocused: Binding<Bool>?
        var lastFocusRequestToken: Int
        var caretScrollBehavior: EditorialCaretScrollBehavior
        weak var textView: UITextView?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>?,
            lastFocusRequestToken: Int,
            caretScrollBehavior: EditorialCaretScrollBehavior
        ) {
            _text = text
            self.isFocused = isFocused
            self.lastFocusRequestToken = lastFocusRequestToken
            self.caretScrollBehavior = caretScrollBehavior
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            scrollSelectionIntoViewIfNeeded(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = true
            scrollSelectionIntoViewIfNeeded(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            scrollSelectionIntoViewIfNeeded(textView)
        }

        @objc
        func dismissKeyboard() {
            isFocused?.wrappedValue = false
            textView?.resignFirstResponder()
        }

        func makeInputAccessoryView(label: String?, tintColor: UIColor) -> UIView? {
            guard let label else { return nil }

            let toolbar = UIToolbar()
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            toolbar.items = [
                UIBarButtonItem.flexibleSpace(),
                {
                    let item = UIBarButtonItem(
                        title: label,
                        style: .done,
                        target: self,
                        action: #selector(dismissKeyboard)
                    )
                    item.tintColor = tintColor
                    item.accessibilityIdentifier = "RecordingKeyboardDismissButton"
                    return item
                }()
            ]
            toolbar.sizeToFit()
            return toolbar
        }

        func scrollSelectionIntoViewIfNeeded(_ textView: UITextView) {
            guard textView.isScrollEnabled else { return }

            DispatchQueue.main.async {
                switch self.caretScrollBehavior {
                case .visibleOnly:
                    let selectedRange = textView.selectedRange
                    guard selectedRange.location != NSNotFound else { return }
                    textView.scrollRangeToVisible(selectedRange)
                case let .pinCurrentLineNearTop(topPadding):
                    guard let textRange = textView.selectedTextRange else { return }
                    let caretRect = textView.caretRect(for: textRange.end)
                    let insets = textView.adjustedContentInset
                    guard let targetOffsetY = EditorialPinnedCaretMetrics.targetContentOffsetY(
                        currentOffsetY: textView.contentOffset.y,
                        viewportHeight: textView.bounds.height,
                        contentHeight: textView.contentSize.height,
                        insetTop: insets.top,
                        insetBottom: insets.bottom,
                        caretRect: caretRect,
                        topPadding: topPadding
                    ) else {
                        return
                    }

                    textView.setContentOffset(
                        CGPoint(x: textView.contentOffset.x, y: targetOffsetY),
                        animated: false
                    )
                }
            }
        }
    }
}
