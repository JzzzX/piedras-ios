import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.95, green: 0.93, blue: 0.89)
    static let backgroundSecondary = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let surface = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let surfaceElevated = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let border = Color(red: 0.82, green: 0.78, blue: 0.70)
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.17)
    static let mutedInk = Color(red: 0.36, green: 0.38, blue: 0.42)
    static let subtleInk = Color(red: 0.53, green: 0.54, blue: 0.58)
    static let accent = Color(red: 0.15, green: 0.45, blue: 0.43)
    static let accentSoft = Color(red: 0.84, green: 0.92, blue: 0.90)
    static let highlight = Color(red: 0.76, green: 0.43, blue: 0.31)
    static let highlightSoft = Color(red: 0.94, green: 0.86, blue: 0.79)
    static let danger = Color(red: 0.70, green: 0.23, blue: 0.19)
    static let success = Color(red: 0.23, green: 0.49, blue: 0.35)

    static let pageGradient = LinearGradient(
        colors: [backgroundSecondary, background],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.31, blue: 0.30),
            Color(red: 0.12, green: 0.19, blue: 0.22),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardShadow = Color.black.opacity(0.06)
}
