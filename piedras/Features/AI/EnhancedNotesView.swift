import SwiftUI

private struct EnhancedNoteChecklistItem: Identifiable {
    let id = UUID().uuidString
    let text: String
    let isDone: Bool
}

private enum EnhancedNoteBlockKind {
    case title(String)
    case section(String)
    case paragraph(String)
    case bullets([String])
    case checklist([EnhancedNoteChecklistItem])
}

private struct EnhancedNoteBlock: Identifiable {
    let id = UUID().uuidString
    let kind: EnhancedNoteBlockKind
}

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header

            if meetingStore.isEnhancing(meetingID: meeting.id) && trimmedContent.isEmpty {
                documentSkeleton
            } else if displayBlocks.isEmpty {
                emptyDocument
            } else {
                documentBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.documentOlive)

                Text("AI Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            Button {
                Task {
                    await meetingStore.generateEnhancedNotes(for: meeting.id)
                }
            } label: {
                Image(systemName: meetingStore.isEnhancing(meetingID: meeting.id) ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canGenerate ? AppTheme.ink : AppTheme.subtleInk)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(AppTheme.documentPaperSecondary)
                    }
            }
            .buttonStyle(.plain)
            .disabled(meetingStore.isEnhancing(meetingID: meeting.id) || !canGenerate)
            .accessibilityLabel(actionAccessibilityLabel)
        }
    }

    private var documentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                render(block)
                    .padding(.bottom, blockSpacing(after: block.kind, index: index))
            }
        }
    }

    @ViewBuilder
    private func render(_ block: EnhancedNoteBlock) -> some View {
        switch block.kind {
        case let .title(title):
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case let .section(title):
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(text):
            Text(text)
                .font(.body)
                .lineSpacing(10)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullets(items):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(AppTheme.ink.opacity(0.82))
                            .frame(width: 5, height: 5)
                            .padding(.top, 10)

                        Text(item)
                            .font(.body)
                            .lineSpacing(9)
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case let .checklist(items):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(item.isDone ? AppTheme.documentOlive : AppTheme.subtleInk)
                            .padding(.top, 4)

                        Text(item.text)
                            .font(.body)
                            .lineSpacing(9)
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var documentSkeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            skeletonLine(width: 130, height: 12, opacity: 0.20)
            skeletonLine(width: 220, height: 24, opacity: 0.28)
            skeletonLine(width: nil, height: 12, opacity: 0.18)
            skeletonLine(width: nil, height: 12, opacity: 0.16)
            skeletonLine(width: 280, height: 12, opacity: 0.14)

            skeletonLine(width: 110, height: 18, opacity: 0.24)
                .padding(.top, 10)
            skeletonLine(width: nil, height: 12, opacity: 0.18)
            skeletonLine(width: nil, height: 12, opacity: 0.16)
            skeletonLine(width: 240, height: 12, opacity: 0.14)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyDocument: some View {
        VStack(alignment: .leading, spacing: 18) {
            skeletonLine(width: 120, height: 12, opacity: 0.18)
            skeletonLine(width: 210, height: 22, opacity: 0.16)
            skeletonLine(width: nil, height: 11, opacity: 0.14)
            skeletonLine(width: nil, height: 11, opacity: 0.12)
            skeletonLine(width: 240, height: 11, opacity: 0.10)
        }
        .padding(.top, 4)
    }

    private func skeletonLine(width: CGFloat?, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppTheme.documentHairline.opacity(opacity))
            .frame(width: width, height: height)
    }

    private var trimmedContent: String {
        meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedBlocks: [EnhancedNoteBlock] {
        parseBlocks(from: trimmedContent)
    }

    private var displayBlocks: [EnhancedNoteBlock] {
        var blocks = parsedBlocks

        if let first = blocks.first,
           case let .title(title) = first.kind,
           normalized(title) == normalized(meeting.displayTitle) {
            blocks.removeFirst()
        }

        return blocks
    }

    private var canGenerate: Bool {
        !meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionAccessibilityLabel: String {
        if meetingStore.isEnhancing(meetingID: meeting.id) {
            return "Generating notes"
        }

        return trimmedContent.isEmpty ? "Generate notes" : "Refresh notes"
    }

    private func blockSpacing(after kind: EnhancedNoteBlockKind, index: Int) -> CGFloat {
        let isLast = index == displayBlocks.count - 1

        switch kind {
        case .title:
            return isLast ? 0 : 18
        case .section:
            return isLast ? 0 : 14
        case .paragraph, .bullets, .checklist:
            return isLast ? 0 : 24
        }
    }

    private func parseBlocks(from content: String) -> [EnhancedNoteBlock] {
        guard !content.isEmpty else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var index = 0
        var blocks: [EnhancedNoteBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !paragraph.isEmpty else {
                paragraphLines.removeAll()
                return
            }

            blocks.append(EnhancedNoteBlock(kind: .paragraph(paragraph)))
            paragraphLines.removeAll()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let title = line.dropPrefix("# ") {
                flushParagraph()
                let kind: EnhancedNoteBlockKind = blocks.isEmpty ? .title(title) : .section(title)
                blocks.append(EnhancedNoteBlock(kind: kind))
                index += 1
                continue
            }

            if let title = line.dropPrefix("## ") ?? line.dropPrefix("### ") {
                flushParagraph()
                blocks.append(EnhancedNoteBlock(kind: .section(title)))
                index += 1
                continue
            }

            if isChecklistLine(line) {
                flushParagraph()
                var items: [EnhancedNoteChecklistItem] = []

                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isChecklistLine(current) else { break }
                    items.append(parseChecklistItem(from: current))
                    index += 1
                }

                blocks.append(EnhancedNoteBlock(kind: .checklist(items)))
                continue
            }

            if isBulletLine(line) {
                flushParagraph()
                var items: [String] = []

                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isBulletLine(current), let bulletText = current.dropBulletPrefix() else { break }
                    items.append(bulletText)
                    index += 1
                }

                blocks.append(EnhancedNoteBlock(kind: .bullets(items)))
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private func isBulletLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
    }

    private func isChecklistLine(_ line: String) -> Bool {
        line.hasPrefix("- [ ] ")
            || line.hasPrefix("- [x] ")
            || line.hasPrefix("- [X] ")
            || line.hasPrefix("[ ] ")
            || line.hasPrefix("[x] ")
            || line.hasPrefix("[X] ")
    }

    private func parseChecklistItem(from line: String) -> EnhancedNoteChecklistItem {
        let isDone = line.contains("[x]") || line.contains("[X]")
        let text = line
            .replacingOccurrences(of: "- [ ] ", with: "")
            .replacingOccurrences(of: "- [x] ", with: "")
            .replacingOccurrences(of: "- [X] ", with: "")
            .replacingOccurrences(of: "[ ] ", with: "")
            .replacingOccurrences(of: "[x] ", with: "")
            .replacingOccurrences(of: "[X] ", with: "")
        return EnhancedNoteChecklistItem(text: text, isDone: isDone)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dropBulletPrefix() -> String? {
        if let value = dropPrefix("- ") {
            return value
        }

        if let value = dropPrefix("* ") {
            return value
        }

        if let value = dropPrefix("• ") {
            return value
        }

        return nil
    }
}
