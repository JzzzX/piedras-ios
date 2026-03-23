import SwiftUI

/// Deprecated: This inline history list has been replaced by `ChatHistoryDrawerView`,
/// which presents session history in a side drawer instead of inline in the chat view.
/// Kept for reference; safe to delete.
struct ChatSessionHistoryList: View {
    let sections: [ChatSessionHistorySection]
    let activeSessionID: String?
    let isInteractionDisabled: Bool
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        if sections.isEmpty {
            EmptyView()
        } else {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.sessions) { session in
                            Button {
                                onSelect(session.id)
                            } label: {
                                row(for: session)
                            }
                            .disabled(isInteractionDisabled)
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(AppStrings.current.deleteAction, role: .destructive) {
                                    onDelete(session.id)
                                }
                                .disabled(isInteractionDisabled)
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(section.bucket.title.uppercased())
                            .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.subtleInk)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .contentMargins(.zero, for: .scrollContent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 96, maxHeight: 260)
        }
    }

    private func row(for session: ChatSession) -> some View {
        let isActive = session.id == activeSessionID

        return HStack(alignment: .center, spacing: 12) {
            RetroIconBadge(systemName: "bubble.left.and.text.bubble.right", size: AppTheme.compactIconSize, symbolSize: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)

                Text(session.historyMetadataLine())
                    .font(AppTheme.dataFont(size: 12))
                    .foregroundStyle(AppTheme.subtleInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(
            borderColor: isActive ? AppTheme.highlight : AppTheme.subtleBorderColor,
            lineWidth: isActive ? 1.5 : AppTheme.subtleBorderWidth
        )
        .contentShape(Rectangle())
    }
}
