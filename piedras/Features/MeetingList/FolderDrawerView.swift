import SwiftUI

struct FolderDrawerView: View {
    @Binding var isPresented: Bool
    let folders: [FolderSummary]
    let activeFolderID: String?
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onDelete: (FolderSummary) -> Void
    let onCreateFolder: () -> Void

    @State private var openSwipeFolderID: String?

    var body: some View {
        if isPresented {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)

                drawerContent
                    .frame(width: drawerWidth)
                    .transition(.move(edge: .leading))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.24), value: isPresented)
            .accessibilityIdentifier("FolderDrawer")
            .onChange(of: isPresented, initial: false) { _, newValue in
                guard !newValue else { return }
                openSwipeFolderID = nil
            }
        }
    }

    private var drawerContent: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                Spacer()
                ProgressView()
                    .tint(AppTheme.brandInk)
                Spacer()
            } else if folders.isEmpty {
                Spacer()
                Text(AppStrings.current.folderEmptyState)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    }
                }
                .accessibilityIdentifier("FolderDrawerList")
            }

            footer
        }
        .background(AppTheme.surface)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: AppTheme.retroBorderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FolderDrawerPanel")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(AppStrings.current.folderDrawerTitle)
                .font(AppTheme.bodyFont(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.brandInk)

            Spacer()

            AppGlassCircleButton(
                systemName: "xmark",
                accessibilityLabel: AppStrings.current.close,
                size: 32
            ) {
                close()
            }
            .accessibilityIdentifier("FolderDrawerCloseButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: AppTheme.retroBorderWidth)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: AppTheme.retroBorderWidth)

            Button(action: onCreateFolder) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.brandInk)

                    Text(AppStrings.current.newFolder)
                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.brandInk)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("FolderDrawerNewFolderButton")
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: FolderSummary) -> some View {
        if folder.isDefault || folder.isRecentlyDeleted {
            folderRowButton(for: folder)
        } else {
            FolderDrawerSwipeDeleteRow(
                folder: folder,
                isActive: folder.id == activeFolderID,
                isOpen: openSwipeFolderID == folder.id,
                onSelect: {
                    onSelect(folder.id)
                    close()
                },
                onDelete: {
                    openSwipeFolderID = nil
                    onDelete(folder)
                },
                onOpenChanged: { shouldOpen in
                    withAnimation(.easeOut(duration: 0.18)) {
                        openSwipeFolderID = shouldOpen ? folder.id : nil
                    }
                }
            )
        }
    }

    private var drawerWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.78, 320)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.24)) {
            isPresented = false
        }
        openSwipeFolderID = nil
    }

    private func folderRowButton(for folder: FolderSummary) -> some View {
        let isActive = folder.id == activeFolderID

        return Button {
            onSelect(folder.id)
            close()
        } label: {
            folderRowLabel(folder: folder, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("FolderDrawerRow_\(folder.id)")
    }

    private func folderRowLabel(folder: FolderSummary, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: folderIconName(isActive: isActive, folder: folder))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.brandInk)

            Text(folder.displayName)
                .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(isActive ? AppTheme.selectedChromeFill : Color.clear)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(AppTheme.brandInk)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
    }

    private func folderIconName(isActive: Bool, folder: FolderSummary) -> String {
        if folder.isRecentlyDeleted {
            return "trash"
        }
        return isActive ? "folder.fill" : "folder"
    }
}

private struct FolderDrawerSwipeDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(configuration.isPressed ? AppTheme.destructiveActionPressedFill : AppTheme.destructiveActionFill)
            )
            .overlay(
                Rectangle()
                    .stroke(AppTheme.destructiveActionBorder, lineWidth: AppTheme.retroBorderWidth)
            )
            .retroHardShadow(
                x: configuration.isPressed ? 0 : AppTheme.retroShadowOffset,
                y: configuration.isPressed ? 0 : AppTheme.retroShadowOffset,
                color: AppTheme.destructiveActionShadow
            )
            .offset(
                x: configuration.isPressed ? AppTheme.retroShadowOffset : 0,
                y: configuration.isPressed ? AppTheme.retroShadowOffset : 0
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FolderDrawerSwipeDeleteRow: View {
    let folder: FolderSummary
    let isActive: Bool
    let isOpen: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onOpenChanged: (Bool) -> Void

    @State private var contentOffset: CGFloat = 0

    var body: some View {
        let isActionPresented = HomeSwipeToDeleteMetrics.isActionPresented(
            forContentOffset: contentOffset,
            isOpen: isOpen
        )
        let isActionHittable = HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: contentOffset)

        ZStack(alignment: .trailing) {
            Button(action: handleRowTap) {
                HStack(spacing: 10) {
                    Image(systemName: isActive ? "folder.fill" : "folder")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.brandInk)

                    Text(folder.displayName)
                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(isActive ? AppTheme.selectedChromeFill : Color.clear)
                .overlay(alignment: .leading) {
                    if isActive {
                        Rectangle()
                            .fill(AppTheme.brandInk)
                            .frame(width: 3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: contentOffset)

            deleteAction
                .offset(x: HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: contentOffset))
                .opacity(isActionPresented ? 1 : 0)
                .allowsHitTesting(isActionHittable)
                .accessibilityHidden(!isActionHittable)
                .zIndex(1)
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .onChange(of: isOpen, initial: true) { _, newValue in
            withAnimation(HomeSwipeToDeleteMetrics.settleAnimation) {
                contentOffset = newValue ? -HomeSwipeToDeleteMetrics.actionWidth : 0
            }
        }
        .accessibilityIdentifier("FolderDrawerRow_\(folder.id)")
    }

    private var deleteAction: some View {
        Button {
            closeRow()
            onDelete()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.surface)

                Text(AppStrings.current.deleteAction.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.surface)
                    .tracking(0.4)
            }
            .frame(width: HomeSwipeToDeleteMetrics.actionWidth, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(FolderDrawerSwipeDeleteButtonStyle())
        .accessibilityLabel(AppStrings.current.deleteFolderAction)
        .accessibilityIdentifier("FolderDrawerDeleteButton_\(folder.id)")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard shouldTrack(value) else { return }
                let baseOffset = isOpen ? -HomeSwipeToDeleteMetrics.actionWidth : 0
                contentOffset = HomeSwipeToDeleteMetrics.clampedContentOffset(baseOffset + value.translation.width)
            }
            .onEnded { value in
                guard shouldTrack(value) else {
                    settle(open: isOpen)
                    return
                }

                let baseOffset = isOpen ? -HomeSwipeToDeleteMetrics.actionWidth : 0
                let finalOffset = HomeSwipeToDeleteMetrics.clampedContentOffset(baseOffset + value.translation.width)
                let shouldOpen = HomeSwipeToDeleteMetrics.shouldSettleOpen(isOpen: isOpen, finalOffset: finalOffset)

                settle(open: shouldOpen)
                onOpenChanged(shouldOpen)
            }
    }

    private func handleRowTap() {
        guard HomeSwipeToDeleteMetrics.isActionPresented(forContentOffset: contentOffset, isOpen: isOpen) else {
            onSelect()
            return
        }

        closeRow()
    }

    private func closeRow() {
        settle(open: false)
        onOpenChanged(false)
    }

    private func settle(open: Bool) {
        withAnimation(HomeSwipeToDeleteMetrics.settleAnimation) {
            contentOffset = open ? -HomeSwipeToDeleteMetrics.actionWidth : 0
        }
    }

    private func shouldTrack(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height)
    }
}
