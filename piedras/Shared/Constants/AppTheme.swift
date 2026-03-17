import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let backgroundSecondary = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let surface = Color.white.opacity(0.74)
    static let surfaceElevated = Color.white.opacity(0.88)
    static let border = Color.white.opacity(0.62)
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let mutedInk = Color(red: 0.31, green: 0.35, blue: 0.41)
    static let subtleInk = Color(red: 0.50, green: 0.55, blue: 0.62)
    static let accent = Color(red: 0.25, green: 0.49, blue: 0.88)
    static let accentSoft = Color(red: 0.87, green: 0.92, blue: 1.00)
    static let highlight = Color(red: 0.93, green: 0.37, blue: 0.32)
    static let highlightSoft = Color(red: 1.00, green: 0.90, blue: 0.87)
    static let danger = Color(red: 0.78, green: 0.25, blue: 0.22)
    static let success = Color(red: 0.20, green: 0.58, blue: 0.42)
    static let ambientBlue = Color(red: 0.77, green: 0.86, blue: 1.00)
    static let ambientMint = Color(red: 0.80, green: 0.94, blue: 0.91)
    static let ambientSand = Color(red: 0.98, green: 0.92, blue: 0.84)

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.99, green: 0.99, blue: 1.00),
            Color(red: 0.96, green: 0.98, blue: 1.00),
            Color(red: 0.95, green: 0.96, blue: 0.99),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.24, blue: 0.33),
            Color(red: 0.11, green: 0.14, blue: 0.22),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardShadow = Color.black.opacity(0.10)
    static let glassShadow = Color.black.opacity(0.12)
}
