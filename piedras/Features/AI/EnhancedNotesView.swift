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
        VStack(alignment: .leading, spacing: 22) {
            header

            if meetingStore.isEnhancing(meetingID: meeting.id) && trimmedContent.isEmpty {
                documentSkeleton
            } else if trimmedContent.isEmpty {
                emptyDocument
            } else {
                documentBody
            }
        }
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.documentOlive)

                Text("AI Summary")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
            }

            Spacer()

            Button {
                Task {
                    await meetingStore.generateEnhancedNotes(for: meeting.id)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: meetingStore.isEnhancing(meetingID: meeting.id) ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(canGenerate ? AppTheme.ink : AppTheme.subtleInk)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    PaperSurface(
                        cornerRadius: 17,
                        fill: AppTheme.documentPaperSecondary,
                        border: AppTheme.documentHairline,
                        shadowOpacity: 0.03
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(meetingStore.isEnhancing(meetingID: meeting.id) || !canGenerate)
        }
    }

    private var documentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                render(block)
                    .padding(.bottom, blockSpacing(after: block.kind))

                if showsDivider(after: block.kind, nextIndex: index) {
                    PaperDivider()
                        .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func render(_ block: EnhancedNoteBlock) -> some View {
        switch block.kind {
        case let .title(title):
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppTheme.ink)

        case let .section(title):
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.top, 6)

        case let .paragraph(text):
            Text(text)
                .font(.body)
                .lineSpacing(8)
                .foregroundStyle(AppTheme.ink)

        case let .bullets(items):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .font(.body.weight(.bold))
                            .foregroundStyle(AppTheme.ink)

                        Text(item)
                            .font(.body)
                            .lineSpacing(7)
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case let .checklist(items):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(item.isDone ? AppTheme.documentOlive : AppTheme.subtleInk)
                            .padding(.top, 2)

                        Text(item.text)
                            .font(.body)
                            .lineSpacing(7)
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var documentSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonLine(width: 180, height: 24, opacity: 0.28)
            skeletonLine(width: 110, height: 12, opacity: 0.22)
            skeletonLine(width: nil, height: 12, opacity: 0.20)
            skeletonLine(width: nil, height: 12, opacity: 0.16)
            skeletonLine(width: 230, height: 12, opacity: 0.14)

            skeletonLine(width: 120, height: 18, opacity: 0.24)
                .padding(.top, 8)
            skeletonLine(width: nil, height: 12, opacity: 0.20)
            skeletonLine(width: nil, height: 12, opacity: 0.16)
            skeletonLine(width: 260, height: 12, opacity: 0.14)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyDocument: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonLine(width: 180, height: 22, opacity: 0.18)
            skeletonLine(width: nil, height: 11, opacity: 0.16)
            skeletonLine(width: nil, height: 11, opacity: 0.12)
            skeletonLine(width: 210, height: 11, opacity: 0.10)
        }
    }

    private func skeletonLine(width: CGFloat?, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppTheme.documentHairline.opacity(opacity))
            .frame(width: width, height: height)
    }

    private var trimmedContent: String {
        meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var blocks: [EnhancedNoteBlock] {
        parseBlocks(from: trimmedContent)
    }

    private var canGenerate: Bool {
        !meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionTitle: String {
        if meetingStore.isEnhancing(meetingID: meeting.id) {
            return "Working"
        }

        return trimmedContent.isEmpty ? "Generate" : "Refresh"
    }

    private func blockSpacing(after kind: EnhancedNoteBlockKind) -> CGFloat {
        switch kind {
        case .title:
            return 16
        case .section:
            return 12
        case .paragraph, .bullets, .checklist:
            return 20
        }
    }

    private func showsDivider(after kind: EnhancedNoteBlockKind, nextIndex: Int) -> Bool {
        guard nextIndex < blocks.count - 1 else { return false }
        switch kind {
        case .paragraph, .bullets, .checklist:
            return false
        case .title, .section:
            return false
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
