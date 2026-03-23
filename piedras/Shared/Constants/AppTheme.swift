import SwiftUI
import UIKit

// MARK: - Retro Macintosh + Paper Texture Theme

enum AppTheme {
    // ── Core Palette ──────────────────────────────────────────────
    /// Manila paper background
    static var background: Color { Color(hex: 0xEAE3D2) }
    /// Slightly darker paper for secondary areas
    static var backgroundSecondary: Color { Color(hex: 0xE2DBCA) }
    /// Bleached paper surface (cards/windows)
    static var surface: Color { Color(hex: 0xF4F0E6) }
    /// Elevated surface (same as surface in retro: no transparency)
    static var surfaceElevated: Color { Color(hex: 0xF4F0E6) }
    /// Hard ink-black border
    static var border: Color { Color(hex: 0x111111) }
    /// Ink black for text
    static var ink: Color { Color(hex: 0x111111) }
    /// Faded ink for secondary text
    static var mutedInk: Color { Color(hex: 0x6A6358) }
    /// Faded ink for tertiary text
    static var subtleInk: Color { Color(hex: 0x8A8578) }
    /// Muted accent (same as ink in retro)
    static var accent: Color { Color(hex: 0x111111) }
    /// Soft accent background
    static var accentSoft: Color { Color(hex: 0xE2DBCA) }
    /// Rubber stamp red – primary highlight
    static var highlight: Color { Color(hex: 0xD9423E) }
    /// Soft highlight background
    static var highlightSoft: Color { Color(hex: 0xF4E6E5) }
    /// Danger – same red
    static var danger: Color { Color(hex: 0xD9423E) }
    /// Success – typewriter green
    static var success: Color { Color(hex: 0x5F824D) }
    /// Ballpoint pen blue
    static var penBlue: Color { Color(hex: 0x2B4C7E) }

    /// Dock / toolbar surface – slightly darker than cards for visual separation
    static var dockSurface: Color { Color(hex: 0xE8E1D0) }

    // Ambient colors (no gradient blobs in retro – flat)
    static var ambientBlue: Color { Color(hex: 0xEAE3D2) }
    static var ambientMint: Color { Color(hex: 0xEAE3D2) }
    static var ambientSand: Color { Color(hex: 0xEAE3D2) }

    // Card colors
    static var homeCard: Color { Color(hex: 0xF4F0E6) }
    static var homeCardBorder: Color { Color(hex: 0x111111) }
    static var homeCardShadow: Color { Color(hex: 0x111111) }

    // Document colors
    static var documentBackground: Color { Color(hex: 0xEAE3D2) }
    static var documentPaper: Color { Color(hex: 0xF4F0E6) }
    static var documentPaperSecondary: Color { Color(hex: 0xEAE3D2) }
    static var documentHairline: Color { Color(hex: 0x111111) }
    static var documentOlive: Color { Color(hex: 0x5F824D) }
    static var documentShadow: Color { Color(hex: 0x111111) }

    // Glass → Retro (no transparency, hard edges)
    static var glassStroke: Color { Color(hex: 0x111111) }
    static var glassHighlight: Color { Color(hex: 0xF4F0E6) }
    static var glassTint: Color { Color(hex: 0xF4F0E6) }
    static var glassShadow: Color { Color(hex: 0x111111) }
    static var glassIconStart: Color { Color(hex: 0xF4F0E6) }
    static var glassIconEnd: Color { Color(hex: 0xEAE3D2) }

    // ── Flat Gradients (no gradient in retro) ─────────────────────
    static var pageGradient: LinearGradient {
        LinearGradient(colors: [background], startPoint: .top, endPoint: .bottom)
    }

    static var documentGradient: LinearGradient {
        LinearGradient(colors: [background], startPoint: .top, endPoint: .bottom)
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x111111), Color(hex: 0x222222)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardShadow: Color { Color(hex: 0x111111) }

    // ── Typography ────────────────────────────────────────────────
    static let editorialBodyLineSpacing: CGFloat = 6
    static let editorialSectionSpacing: CGFloat = 18
    static let editorialParagraphSpacing: CGFloat = 16

    /// Monospace body font (replaces Songti editorial font)
    static func editorialFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    /// Monospace emphasis font
    static func editorialEmphasisFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// UIFont equivalent for UIKit bridging
    static func editorialUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// System sans-serif body font for natural language content.
    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Monospaced font for timestamps, versions, and technical data.
    static func dataFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// UIKit bridge for natural language content.
    static func bodyUIFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    // ── Retro Dimensions ──────────────────────────────────────────
    static let retroBorderWidth: CGFloat = 2
    static let retroCornerRadius: CGFloat = 0
    static let retroShadowOffset: CGFloat = 4
    static let retroTitleBarHeight: CGFloat = 24
    static let subtleBorderWidth: CGFloat = 1
    static let subtleBorderColor: Color = Color(hex: 0x111111).opacity(0.13)
    static let compactIconSize: CGFloat = 32
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Retro Window ViewModifier

/// Mac OS 9 style window with hard border, zero radius, hard drop shadow
struct RetroWindowModifier: ViewModifier {
    var hasTitleBar: Bool = false
    var titleBarLabel: String = ""

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if hasTitleBar {
                RetroTitleBar(label: titleBarLabel)
            }
            content
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
    }
}

extension View {
    func retroWindow(titleBar: String? = nil) -> some View {
        modifier(RetroWindowModifier(
            hasTitleBar: titleBar != nil,
            titleBarLabel: titleBar ?? ""
        ))
    }

    func softCard(
        fill: Color = AppTheme.surface,
        borderColor: Color = AppTheme.subtleBorderColor,
        lineWidth: CGFloat = AppTheme.subtleBorderWidth
    ) -> some View {
        modifier(SoftCardModifier(fill: fill, borderColor: borderColor, lineWidth: lineWidth))
    }

    /// Hard pixel-perfect drop shadow that does NOT ghost text.
    /// Uses a background offset rectangle instead of `.shadow()`.
    func retroHardShadow(
        x: CGFloat = AppTheme.retroShadowOffset,
        y: CGFloat = AppTheme.retroShadowOffset,
        color: Color = AppTheme.border
    ) -> some View {
        self.background(alignment: .topLeading) {
            Rectangle()
                .fill(color)
                .offset(x: x, y: y)
        }
    }
}

struct SoftCardModifier: ViewModifier {
    var fill: Color = AppTheme.surface
    var borderColor: Color = AppTheme.subtleBorderColor
    var lineWidth: CGFloat = AppTheme.subtleBorderWidth

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: lineWidth)
            )
    }
}

// MARK: - Retro Title Bar

/// Mac OS 9 striped title bar with close box
struct RetroTitleBar: View {
    let label: String
    var showCloseBox: Bool = false
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if showCloseBox {
                RetroCloseBox(action: onClose ?? {})
            }

            Spacer()

            Text(label)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(AppTheme.surface)

            Spacer()

            // Balance the close box
            if showCloseBox {
                Color.clear.frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: AppTheme.retroTitleBarHeight)
        .background(
            RetroStripePattern()
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: AppTheme.retroBorderWidth)
        }
    }
}

// MARK: - Stripe Pattern for Title Bar

struct RetroStripePattern: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let stripeWidth: CGFloat = 2
                var x: CGFloat = 0
                var isBlack = true
                while x < size.width {
                    let rect = CGRect(x: x, y: 0, width: stripeWidth, height: size.height)
                    context.fill(
                        Path(rect),
                        with: .color(isBlack ? AppTheme.ink : AppTheme.surface)
                    )
                    x += stripeWidth
                    isBlack.toggle()
                }
            }
        }
    }
}

// MARK: - Retro Close Box

struct RetroCloseBox: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Rectangle()
                .fill(isHovered ? AppTheme.ink : AppTheme.surface)
                .frame(width: 14, height: 14)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.ink, lineWidth: AppTheme.retroBorderWidth)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Retro Button Style

struct RetroButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundStyle(isPrimary ? AppTheme.surface : AppTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isPrimary ? AppTheme.ink : AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.ink, lineWidth: AppTheme.retroBorderWidth)
            )
            .retroHardShadow(
                x: configuration.isPressed ? 0 : AppTheme.retroShadowOffset,
                y: configuration.isPressed ? 0 : AppTheme.retroShadowOffset
            )
            .offset(
                x: configuration.isPressed ? AppTheme.retroShadowOffset : 0,
                y: configuration.isPressed ? AppTheme.retroShadowOffset : 0
            )
    }
}

extension ButtonStyle where Self == RetroButtonStyle {
    static var retro: RetroButtonStyle { RetroButtonStyle() }
    static var retroPrimary: RetroButtonStyle { RetroButtonStyle(isPrimary: true) }
}

// MARK: - Retro Stamp Label

struct RetroStampLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(AppTheme.highlight)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.highlight, lineWidth: AppTheme.retroBorderWidth)
            )
            .rotationEffect(.degrees(-5))
    }
}

// MARK: - Retro Checkerboard Progress Bar

struct RetroCheckerboardProgress: View {
    var progress: Double = 1.0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(AppTheme.surface)

                // Fill with checkerboard
                Canvas { context, size in
                    let cellSize: CGFloat = 8
                    let fillWidth = size.width * min(max(progress, 0), 1)

                    for row in 0..<Int(ceil(size.height / cellSize)) {
                        for col in 0..<Int(ceil(fillWidth / cellSize)) {
                            let isBlack = (row + col) % 2 == 0
                            let rect = CGRect(
                                x: CGFloat(col) * cellSize,
                                y: CGFloat(row) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                            context.fill(
                                Path(rect),
                                with: .color(isBlack ? AppTheme.ink : AppTheme.surface)
                            )
                        }
                    }
                }
                .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 16)
        .overlay(
            Rectangle()
                .stroke(AppTheme.ink, lineWidth: AppTheme.retroBorderWidth)
        )
    }
}

// MARK: - Retro Blinking Cursor

struct RetroBlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Text("█")
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundStyle(AppTheme.ink)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0).repeatForever(autoreverses: true).speed(0.8)) {
                    isVisible.toggle()
                }
            }
    }
}

// MARK: - Retro Divider

struct RetroDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(height: AppTheme.retroBorderWidth)
            .padding(.leading, inset)
    }
}

struct ThinDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AppTheme.subtleBorderColor)
            .frame(height: AppTheme.subtleBorderWidth)
            .padding(.leading, inset)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(AppTheme.bodyFont(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.subtleInk)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Retro Card (replaces PaperCard / AppGlassCard)

struct RetroCard<Content: View>: View {
    var titleBar: String? = nil
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .retroWindow(titleBar: titleBar)
    }
}

// MARK: - Retro Icon Badge (replaces GlassIconBadge)

struct RetroIconBadge: View {
    let systemName: String
    var size: CGFloat = 44
    var symbolSize: CGFloat? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                )

            Image(systemName: systemName)
                .font(.system(size: symbolSize ?? size * 0.38, weight: .bold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Retro Square Button (replaces AppGlassCircleButton)

struct RetroSquareButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = 44
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(prominent ? AppTheme.ink : AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )

                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(prominent ? AppTheme.surface : AppTheme.ink)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Session Count Badge

/// Small red badge showing a count, positioned at the top-right of its parent.
struct SessionCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(AppTheme.highlight)
        }
    }
}

// MARK: - Retro Noise Overlay

struct RetroNoiseOverlay: View {
    var body: some View {
        Canvas { context, size in
            // Simple grain effect
            for _ in 0..<Int(size.width * size.height * 0.003) {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let dotSize: CGFloat = 1
                let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                context.fill(
                    Path(rect),
                    with: .color(.black.opacity(Double.random(in: 0.02...0.06)))
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Retro Raised Edge (Mac OS 9 bevel)

/// Classic Mac OS 9 raised bevel: 1px white highlight on top, 2px black divider below.
/// Place at the top of a toolbar to visually separate it from content above.
struct RetroRaisedEdge: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white)
                .frame(height: 1)
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: AppTheme.retroBorderWidth)
        }
    }
}
