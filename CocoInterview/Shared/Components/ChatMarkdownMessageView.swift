import SwiftUI

struct ChatMarkdownMessageView: View {
    let markdown: String
    var accessibilityIdentifier: String? = nil

    private var blocks: [MarkdownDocumentFormatter.Block] {
        MarkdownDocumentFormatter.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownDocumentFormatter.Block) -> some View {
        switch block.kind {
        case .heading:
            Text(block.attributedText)
                .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph:
            Text(block.attributedText)
                .font(AppTheme.bodyFont(size: 16))
                .lineSpacing(6)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case let .orderedList(index):
            HStack(alignment: .top, spacing: 8) {
                Text("\(index).")
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.subtleInk)
                    .padding(.top, 1)

                Text(block.attributedText)
                    .font(AppTheme.bodyFont(size: 16))
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(AppTheme.ink)
                    .frame(width: 4, height: 4)
                    .padding(.top, 8)

                Text(block.attributedText)
                    .font(AppTheme.bodyFont(size: 16))
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .checklist(isChecked):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(isChecked ? AppTheme.ink : .clear)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.ink, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .padding(.top, 3)

                Text(block.attributedText)
                    .font(AppTheme.bodyFont(size: 16))
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 3)

                Text(block.attributedText)
                    .font(AppTheme.bodyFont(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
