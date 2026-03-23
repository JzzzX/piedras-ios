import SwiftUI

// MARK: - Chat History Drawer

/// A reusable side drawer that displays chat session history,
/// sliding in from the trailing edge with a dimmed overlay.
struct ChatHistoryDrawerView: View {
    @Binding var isPresented: Bool
    let sections: [ChatSessionHistorySection]
    let activeSessionID: String?
    let scopeIcon: String
    let isInteractionDisabled: Bool
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onNewChat: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if isPresented {
            ZStack(alignment: .trailing) {
                // Dimmed overlay
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)

                // Drawer panel
                drawerContent
                    .frame(width: drawerWidth)
                    .offset(x: dragOffset)
                    .gesture(dismissDragGesture)
                    .transition(.move(edge: .trailing))
            }
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
    }

    // MARK: - Drawer Content

    private var drawerContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: scopeIcon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(AppStrings.current.chatHistoryTitle)
                        .font(AppTheme.bodyFont(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer()

                AppGlassCircleButton(
                    systemName: "xmark",
                    accessibilityLabel: AppStrings.current.close,
                    size: 32
                ) {
                    close()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: AppTheme.retroBorderWidth)
            }

            // New chat button
            Button {
                onNewChat()
                close()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(AppStrings.current.newChat)
                        .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isInteractionDisabled)
            .overlay(alignment: .bottom) {
                ThinDivider()
            }

            // Session list
            if sections.isEmpty {
                Spacer()
                Text(AppStrings.current.chatHistoryDrawerEmpty)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
                    .padding(20)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sections) { section in
                            sectionHeader(section.bucket.title)

                            ForEach(section.sessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
            }
        }
        .background(AppTheme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: AppTheme.retroBorderWidth)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppTheme.bodyFont(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.subtleInk)
            .tracking(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: ChatSession) -> some View {
        let isActive = session.id == activeSessionID

        return Button {
            onSelect(session.id)
            close()
        } label: {
            HStack(spacing: 10) {
                RetroIconBadge(
                    systemName: scopeIcon,
                    size: 28,
                    symbolSize: 11
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)

                    Text(session.historyMetadataLine())
                        .font(AppTheme.dataFont(size: 10))
                        .foregroundStyle(AppTheme.subtleInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? AppTheme.highlightSoft : Color.clear)
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(AppTheme.highlight)
                        .frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(AppStrings.current.deleteAction, role: .destructive) {
                onDelete(session.id)
            }
            .disabled(isInteractionDisabled)
        }
    }

    // MARK: - Helpers

    private var drawerWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.75, 320)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = value.translation.width
                if translation > 0 {
                    dragOffset = translation
                }
            }
            .onEnded { value in
                if value.translation.width > 80 {
                    close()
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    dragOffset = 0
                }
            }
    }
}
