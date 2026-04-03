import SwiftUI

enum HomeSwipeToDeleteMetrics {
    static let actionWidth: CGFloat = 72
    static let actionHeight: CGFloat = 72
    static let actionRevealThreshold: CGFloat = 4
    static let actionHitTestingProgress: CGFloat = 0.72
    static let settleAnimation: Animation = .interactiveSpring(response: 0.22, dampingFraction: 0.9, blendDuration: 0.08)

    static func clampedContentOffset(_ value: CGFloat) -> CGFloat {
        min(0, max(-actionWidth, value))
    }

    static func revealProgress(forContentOffset value: CGFloat) -> CGFloat {
        let clampedValue = clampedContentOffset(value)
        return min(1, max(0, -clampedValue / actionWidth))
    }

    static func actionOffset(forContentOffset value: CGFloat) -> CGFloat {
        (1 - revealProgress(forContentOffset: value)) * actionWidth
    }

    static func isActionPresented(forContentOffset value: CGFloat, isOpen: Bool) -> Bool {
        isOpen || revealProgress(forContentOffset: value) > actionRevealThreshold / actionWidth
    }

    static func isActionHittable(forContentOffset value: CGFloat) -> Bool {
        revealProgress(forContentOffset: value) >= actionHitTestingProgress
    }

    static func shouldSettleOpen(isOpen: Bool, finalOffset: CGFloat) -> Bool {
        let clampedValue = clampedContentOffset(finalOffset)
        return isOpen
            ? clampedValue < -actionWidth * 0.35
            : clampedValue < -actionWidth * 0.45
    }
}

private struct MeetingRowDeleteButtonStyle: ButtonStyle {
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

struct HomeSwipeToDeleteRow: View {
    let snapshot: MeetingRowSnapshot
    let isOpen: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onOpenChanged: (Bool) -> Void

    @State private var contentOffset: CGFloat = 0

    var body: some View {
        let isActionPresented = HomeSwipeToDeleteMetrics.isActionPresented(forContentOffset: contentOffset, isOpen: isOpen)
        let isActionHittable = HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: contentOffset)

        ZStack(alignment: .trailing) {
            MeetingRowView(snapshot: snapshot, onOpen: handleRowTap)
                .offset(x: contentOffset)

            deleteAction
                .offset(x: HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: contentOffset))
                .opacity(isActionPresented ? 1 : 0)
                .allowsHitTesting(isActionHittable)
                .accessibilityHidden(!isActionHittable)
                .accessibilityIdentifier(isActionHittable ? "MeetingRowDeleteButton" : "MeetingRowDeleteButtonHidden")
                .zIndex(1)
        }
        .contentShape(Rectangle())
        .clipped()
        .highPriorityGesture(dragGesture)
        .onChange(of: isOpen, initial: true) { _, newValue in
            withAnimation(HomeSwipeToDeleteMetrics.settleAnimation) {
                contentOffset = newValue ? -HomeSwipeToDeleteMetrics.actionWidth : 0
            }
        }
    }

    private var deleteAction: some View {
        Button {
            closeRow()
            onDelete()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.surface)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .frame(width: 48, height: HomeSwipeToDeleteMetrics.actionHeight)
        .buttonStyle(MeetingRowDeleteButtonStyle())
        .padding(.trailing, 14)
        .accessibilityLabel(AppStrings.current.deleteNoteAction)
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
            onOpen()
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
