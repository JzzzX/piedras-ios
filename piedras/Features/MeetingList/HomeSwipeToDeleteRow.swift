import SwiftUI

enum HomeSwipeToDeleteMetrics {
    static let actionWidth: CGFloat = 72
    static let actionHeight: CGFloat = 72
    static let actionRevealThreshold: CGFloat = 4
    static let actionHitTestingProgress: CGFloat = 0.72
    static let settleAnimation: Animation = .interactiveSpring(response: 0.22, dampingFraction: 0.9, blendDuration: 0.08)

    static func totalActionWidth(actionCount: Int) -> CGFloat {
        actionWidth * CGFloat(max(actionCount, 1))
    }

    static func clampedContentOffset(_ value: CGFloat, actionCount: Int = 1) -> CGFloat {
        min(0, max(-totalActionWidth(actionCount: actionCount), value))
    }

    static func revealProgress(forContentOffset value: CGFloat, actionCount: Int = 1) -> CGFloat {
        let totalWidth = totalActionWidth(actionCount: actionCount)
        let clampedValue = clampedContentOffset(value, actionCount: actionCount)
        return min(1, max(0, -clampedValue / totalWidth))
    }

    static func actionOffset(forContentOffset value: CGFloat, actionCount: Int = 1) -> CGFloat {
        (1 - revealProgress(forContentOffset: value, actionCount: actionCount)) * totalActionWidth(actionCount: actionCount)
    }

    static func isActionPresented(forContentOffset value: CGFloat, isOpen: Bool, actionCount: Int = 1) -> Bool {
        isOpen || revealProgress(forContentOffset: value, actionCount: actionCount) > actionRevealThreshold / totalActionWidth(actionCount: actionCount)
    }

    static func isActionHittable(forContentOffset value: CGFloat, actionCount: Int = 1) -> Bool {
        let clampedValue = clampedContentOffset(value, actionCount: actionCount)
        return -clampedValue >= actionWidth * actionHitTestingProgress
    }

    static func shouldSettleOpen(isOpen: Bool, finalOffset: CGFloat, actionCount: Int = 1) -> Bool {
        let totalWidth = totalActionWidth(actionCount: actionCount)
        let clampedValue = clampedContentOffset(finalOffset, actionCount: actionCount)
        return isOpen
            ? clampedValue < -totalWidth * 0.35
            : clampedValue < -totalWidth * 0.45
    }

    static func prefersHorizontalPan(velocity: CGPoint) -> Bool {
        abs(velocity.x) > abs(velocity.y)
    }
}

enum HomeSwipeRowActionRole {
    case primary
    case destructive
}

struct HomeSwipeRowAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let role: HomeSwipeRowActionRole
    let action: () -> Void
}

private struct MeetingRowSwipeActionButtonStyle: ButtonStyle {
    let role: HomeSwipeRowActionRole

    func makeBody(configuration: Configuration) -> some View {
        let fillColor: Color = switch role {
        case .primary:
            configuration.isPressed ? AppTheme.primaryActionPressedFill : AppTheme.primaryActionFill
        case .destructive:
            configuration.isPressed ? AppTheme.destructiveActionPressedFill : AppTheme.destructiveActionFill
        }
        let borderColor: Color = switch role {
        case .primary:
            AppTheme.primaryActionPressedFill
        case .destructive:
            AppTheme.destructiveActionBorder
        }
        let shadowColor: Color = switch role {
        case .primary:
            AppTheme.border
        case .destructive:
            AppTheme.destructiveActionShadow
        }

        configuration.label
            .background(
                Rectangle()
                    .fill(fillColor)
            )
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: AppTheme.retroBorderWidth)
            )
            .retroHardShadow(
                x: configuration.isPressed ? 0 : AppTheme.retroShadowOffset,
                y: configuration.isPressed ? 0 : AppTheme.retroShadowOffset,
                color: shadowColor
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
    let actions: [HomeSwipeRowAction]
    let onOpenChanged: (Bool) -> Void

    @State private var contentOffset: CGFloat = 0

    var body: some View {
        let actionCount = max(actions.count, 1)
        let isActionPresented = HomeSwipeToDeleteMetrics.isActionPresented(
            forContentOffset: contentOffset,
            isOpen: isOpen,
            actionCount: actionCount
        )
        let isActionHittable = HomeSwipeToDeleteMetrics.isActionHittable(
            forContentOffset: contentOffset,
            actionCount: actionCount
        )

        ZStack(alignment: .trailing) {
            MeetingRowView(snapshot: snapshot, onOpen: handleRowTap)
                .offset(x: contentOffset)

            actionStrip
                .offset(
                    x: HomeSwipeToDeleteMetrics.actionOffset(
                        forContentOffset: contentOffset,
                        actionCount: actionCount
                    )
                )
                .opacity(isActionPresented ? 1 : 0)
                .allowsHitTesting(isActionHittable)
                .accessibilityHidden(!isActionHittable)
                .zIndex(1)
        }
        .contentShape(Rectangle())
        .clipped()
        .simultaneousGesture(dragGesture(actionCount: actionCount))
        .onChange(of: isOpen, initial: true) { _, newValue in
            withAnimation(HomeSwipeToDeleteMetrics.settleAnimation) {
                contentOffset = newValue
                    ? -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: actionCount)
                    : 0
            }
        }
    }

    private var actionStrip: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: HomeSwipeRowAction) -> some View {
        let isHittable = HomeSwipeToDeleteMetrics.isActionHittable(
            forContentOffset: contentOffset,
            actionCount: actions.count
        )

        return Button {
            closeRow()
            action.action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.surface)

                Text(action.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.surface)
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(
                width: HomeSwipeToDeleteMetrics.actionWidth,
                height: HomeSwipeToDeleteMetrics.actionHeight
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MeetingRowSwipeActionButtonStyle(role: action.role))
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityIdentifier(
            isHittable
                ? action.accessibilityIdentifier
                : "\(action.accessibilityIdentifier)Hidden"
        )
    }

    private func handleRowTap() {
        guard HomeSwipeToDeleteMetrics.isActionPresented(
            forContentOffset: contentOffset,
            isOpen: isOpen,
            actionCount: actions.count
        ) else {
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
            contentOffset = open
                ? -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: actions.count)
                : 0
        }
    }

    private func handlePanChanged(_ translationX: CGFloat, actionCount: Int) {
        let baseOffset = isOpen
            ? -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: actionCount)
            : 0
        contentOffset = HomeSwipeToDeleteMetrics.clampedContentOffset(
            baseOffset + translationX,
            actionCount: actionCount
        )
    }

    private func handlePanEnded(_ translationX: CGFloat, actionCount: Int) {
        let baseOffset = isOpen
            ? -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: actionCount)
            : 0
        let finalOffset = HomeSwipeToDeleteMetrics.clampedContentOffset(
            baseOffset + translationX,
            actionCount: actionCount
        )
        let shouldOpen = HomeSwipeToDeleteMetrics.shouldSettleOpen(
            isOpen: isOpen,
            finalOffset: finalOffset,
            actionCount: actionCount
        )

        settle(open: shouldOpen)
        onOpenChanged(shouldOpen)
    }

    private func dragGesture(actionCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard shouldTrack(value) else { return }
                handlePanChanged(value.translation.width, actionCount: actionCount)
            }
            .onEnded { value in
                guard shouldTrack(value) else {
                    settle(open: isOpen)
                    return
                }

                handlePanEnded(value.translation.width, actionCount: actionCount)
            }
    }

    private func shouldTrack(_ value: DragGesture.Value) -> Bool {
        HomeSwipeToDeleteMetrics.prefersHorizontalPan(
            velocity: CGPoint(x: value.translation.width, y: value.translation.height)
        )
    }
}
