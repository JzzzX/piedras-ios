import SwiftUI
import UIKit

// MARK: - Retro Glass Style (kept for API compatibility)

enum AppGlassStyle {
    case regular
    case clear
}

enum GlassIconShape {
    case circle
    case rounded(CGFloat)
}

// MARK: - Retro Backdrop (replaces gradient blobs with flat paper)

struct AppGlassBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            RetroNoiseOverlay()
        }
    }
}

struct DocumentBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            RetroNoiseOverlay()
        }
    }
}

// MARK: - Retro Surface (replaces frosted glass)
// NOTE: AppGlassSurface is used as a .background {} shape, so shadow is fine here
// since it only shadows the shape, not text content.

struct AppGlassSurface: View {
    var cornerRadius: CGFloat = 0
    var style: AppGlassStyle = .regular
    var borderOpacity: Double = 1.0
    var shadowOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Hard shadow layer (behind)
            if shadowOpacity > 0.05 {
                Rectangle()
                    .fill(AppTheme.border)
                    .offset(x: AppTheme.retroShadowOffset, y: AppTheme.retroShadowOffset)
            }

            // Main surface
            Rectangle()
                .fill(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                )
        }
    }
}

// MARK: - Retro Card (replaces AppGlassCard)

struct AppGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 0
    var style: AppGlassStyle = .regular
    var padding: CGFloat = 20
    var shadowOpacity: Double = 1.0
    var subtle = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(
                        subtle ? AppTheme.subtleBorderColor : AppTheme.border,
                        lineWidth: subtle ? AppTheme.subtleBorderWidth : AppTheme.retroBorderWidth
                    )
            )
            .retroHardShadow(
                x: !subtle && shadowOpacity > 0.05 ? AppTheme.retroShadowOffset : 0,
                y: !subtle && shadowOpacity > 0.05 ? AppTheme.retroShadowOffset : 0
            )
    }
}

// MARK: - Retro Readable Panel

struct AppReadableGlassPanel: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.border)
                .offset(x: AppTheme.retroShadowOffset, y: AppTheme.retroShadowOffset)

            Rectangle()
                .fill(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                )
        }
    }
}

// MARK: - Paper Surface (retro version)
// NOTE: PaperSurface is only used as .background {}, so the shadow here is safe.

struct PaperSurface: View {
    var cornerRadius: CGFloat = 0
    var fill: Color = AppTheme.surface
    var border: Color = AppTheme.border
    var shadowOpacity: Double = 1.0

    var body: some View {
        ZStack {
            if shadowOpacity > 0.05 {
                Rectangle()
                    .fill(AppTheme.border)
                    .offset(x: AppTheme.retroShadowOffset, y: AppTheme.retroShadowOffset)
            }

            Rectangle()
                .fill(fill)
                .overlay(
                    Rectangle()
                        .stroke(border, lineWidth: AppTheme.retroBorderWidth)
                )
        }
    }
}

// MARK: - Paper Card (retro version)

struct PaperCard<Content: View>: View {
    var cornerRadius: CGFloat = 0
    var fill: Color = AppTheme.surface
    var border: Color = AppTheme.border
    var padding: CGFloat = 18
    var shadowOpacity: Double = 1.0
    var subtle = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(
                Rectangle()
                    .stroke(
                        subtle ? AppTheme.subtleBorderColor : border,
                        lineWidth: subtle ? AppTheme.subtleBorderWidth : AppTheme.retroBorderWidth
                    )
            )
            .retroHardShadow(
                x: !subtle && shadowOpacity > 0.05 ? AppTheme.retroShadowOffset : 0,
                y: !subtle && shadowOpacity > 0.05 ? AppTheme.retroShadowOffset : 0
            )
    }
}

// MARK: - Retro Dividers

struct AppGlassDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(height: AppTheme.retroBorderWidth)
            .padding(.leading, inset)
    }
}

struct PaperDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(height: AppTheme.retroBorderWidth)
            .padding(.leading, inset)
    }
}

// MARK: - Retro Square Button (replaces glass circle button)

struct AppGlassCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = 44
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(prominent ? AppTheme.primaryActionFill : AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(prominent ? AppTheme.brandInk : AppTheme.selectedChromeBorder, lineWidth: AppTheme.retroBorderWidth)
                    )

                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(prominent ? AppTheme.primaryActionForeground : AppTheme.brandInk)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(SharedChromePressStyle(prominent: prominent))
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Retro Icon Badge (replaces glass icon badge)

struct GlassIconBadge: View {
    let systemName: String
    var size: CGFloat = 44
    var symbolSize: CGFloat? = nil
    var shape: GlassIconShape = .rounded(0)

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.noteIconWash)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.retroBorderWidth)
                )

            Image(systemName: systemName)
                .font(.system(size: symbolSize ?? size * 0.38, weight: .bold))
                .foregroundStyle(AppTheme.brandInkMuted)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Retro Capsule Button (replaces glass capsule)

struct AppGlassCapsuleButton<Label: View>: View {
    var prominent = false
    var minHeight: CGFloat = 52
    var fillsWidth = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(minHeight: minHeight)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(prominent ? AppTheme.primaryActionFill : AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(prominent ? AppTheme.brandInk : AppTheme.selectedChromeBorder, lineWidth: AppTheme.retroBorderWidth)
                )
                .retroHardShadow()
        }
        .buttonStyle(SharedChromePressStyle(prominent: prominent))
    }
}

private struct SharedChromePressStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Rectangle()
                    .fill(prominent ? AppTheme.primaryActionPressedFill : AppTheme.selectedChromeFill)
                    .opacity(configuration.isPressed ? (prominent ? 0.22 : 0.55) : 0)
            }
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
