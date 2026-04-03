import SwiftUI

struct FolderDrawerView: View {
    @Binding var isPresented: Bool
    let folders: [FolderSummary]
    let activeFolderID: String?
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onCreateFolder: () -> Void

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

    private func folderRow(_ folder: FolderSummary) -> some View {
        let isActive = folder.id == activeFolderID

        return Button {
            onSelect(folder.id)
            close()
        } label: {
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
        .accessibilityIdentifier("FolderDrawerRow_\(folder.id)")
    }

    private var drawerWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.78, 320)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.24)) {
            isPresented = false
        }
    }
}
