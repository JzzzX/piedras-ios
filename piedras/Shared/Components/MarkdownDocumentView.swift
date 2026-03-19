import Foundation
import SwiftUI

struct MarkdownDocumentView: View {
    let markdown: String
    var placeholder: String = "No notes yet."
    var minHeight: CGFloat = 420
    var accessibilityIdentifier: String? = nil

    private var blocks: [MarkdownDocumentFormatter.Block] {
        MarkdownDocumentFormatter.blocks(from: markdown)
    }

    private var hasContent: Bool {
        !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasContent {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            } else {
                Text(placeholder)
                    .font(AppTheme.editorialFont(size: 17))
                    .foregroundStyle(AppTheme.subtleInk)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownDocumentFormatter.Block) -> some View {
        switch block.kind {
        case let .heading(level):
            Text(block.attributedText)
                .font(level <= 1 ? AppTheme.editorialEmphasisFont(size: 24) : AppTheme.editorialEmphasisFont(size: 20))
                .foregroundStyle(AppTheme.ink)
                .padding(.top, level <= 1 ? 4 : 2)
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph:
            Text(block.attributedText)
                .font(AppTheme.editorialFont(size: 15))
                .lineSpacing(AppTheme.editorialBodyLineSpacing)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(AppTheme.ink)
                    .frame(width: 4, height: 4)
                    .padding(.top, 7)

                Text(block.attributedText)
                    .font(AppTheme.editorialFont(size: 15))
                    .lineSpacing(AppTheme.editorialBodyLineSpacing)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .checklist(isChecked):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(isChecked ? AppTheme.ink : .clear)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.ink, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .padding(.top, 3)

                Text(block.attributedText)
                    .font(AppTheme.editorialFont(size: 15))
                    .lineSpacing(AppTheme.editorialBodyLineSpacing)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 3)

                Text(block.attributedText)
                    .font(AppTheme.editorialFont(size: 14))
                    .lineSpacing(AppTheme.editorialBodyLineSpacing)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }
}

enum MarkdownDocumentFormatter {
    enum BlockKind {
        case heading(level: Int)
        case paragraph
        case bullet
        case checklist(isChecked: Bool)
        case quote

        var isListLike: Bool {
            switch self {
            case .bullet, .checklist:
                return true
            case .heading, .paragraph, .quote:
                return false
            }
        }
    }

    struct Block {
        let kind: BlockKind
        let source: String

        var attributedText: AttributedString {
            guard !source.isEmpty else { return AttributedString("") }

            if let attributed = try? AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                return attributed
            }

            return AttributedString(source)
        }

        var plainText: String {
            attributedText.characters.reduce(into: "") { partialResult, character in
                partialResult.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func blocks(from markdown: String) -> [Block] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return []
        }

        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                blocks.append(Block(kind: .paragraph, source: text))
            }

            paragraphLines.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let text = quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(Block(kind: .quote, source: text))
            }
            quoteLines.removeAll()
        }

        for rawLine in normalized.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                flushQuote()
                continue
            }

            if let quote = trimmed.dropPrefix("> ") {
                flushParagraph()
                quoteLines.append(quote)
                continue
            } else {
                flushQuote()
            }

            if let heading = trimmed.headingContent(level: 1) {
                flushParagraph()
                blocks.append(Block(kind: .heading(level: 1), source: heading))
                continue
            }

            if let heading = trimmed.headingContent(level: 2) {
                flushParagraph()
                blocks.append(Block(kind: .heading(level: 2), source: heading))
                continue
            }

            if let heading = trimmed.headingContent(level: 3) {
                flushParagraph()
                blocks.append(Block(kind: .heading(level: 3), source: heading))
                continue
            }

            if let checklist = trimmed.checklistContent(isChecked: true) {
                flushParagraph()
                blocks.append(Block(kind: .checklist(isChecked: true), source: checklist))
                continue
            }

            if let checklist = trimmed.checklistContent(isChecked: false) {
                flushParagraph()
                blocks.append(Block(kind: .checklist(isChecked: false), source: checklist))
                continue
            }

            if let bullet = trimmed.bulletContent() {
                flushParagraph()
                blocks.append(Block(kind: .bullet, source: bullet))
                continue
            }

            paragraphLines.append(trimmed)
        }

        flushParagraph()
        flushQuote()
        return blocks
    }

    static func plainText(from markdown: String) -> String {
        let blocks = blocks(from: markdown)
        guard !blocks.isEmpty else { return "" }

        var result = ""
        var previousWasList = false

        for block in blocks {
            let text: String

            switch block.kind {
            case .heading:
                text = block.plainText
            case .paragraph:
                text = block.plainText
            case .bullet:
                text = "• \(block.plainText)"
            case let .checklist(isChecked):
                text = "\(isChecked ? "☑" : "□") \(block.plainText)"
            case .quote:
                text = block.plainText
            }

            guard !text.isEmpty else { continue }

            if !result.isEmpty {
                result.append(previousWasList && block.kind.isListLike ? "\n" : "\n\n")
            }

            result.append(text)
            previousWasList = block.kind.isListLike
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func headingContent(level: Int) -> String? {
        let prefix = String(repeating: "#", count: level) + " "
        return dropPrefix(prefix)
    }

    func checklistContent(isChecked: Bool) -> String? {
        if isChecked {
            return dropPrefix("- [x] ")
                ?? dropPrefix("- [X] ")
                ?? dropPrefix("* [x] ")
                ?? dropPrefix("* [X] ")
                ?? dropPrefix("[x] ")
                ?? dropPrefix("[X] ")
        }

        return dropPrefix("- [ ] ")
            ?? dropPrefix("* [ ] ")
            ?? dropPrefix("[ ] ")
    }

    func bulletContent() -> String? {
        dropPrefix("- ") ?? dropPrefix("* ") ?? dropPrefix("• ")
    }

    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
