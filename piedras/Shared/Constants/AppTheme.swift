import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let backgroundSecondary = Color(red: 0.98, green: 0.96, blue: 0.93)
    static let surface = Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.72)
    static let surfaceElevated = Color(red: 1.00, green: 0.99, blue: 0.97).opacity(0.90)
    static let border = Color.white.opacity(0.58)
    static let ink = Color(red: 0.23, green: 0.18, blue: 0.14)
    static let mutedInk = Color(red: 0.41, green: 0.34, blue: 0.28)
    static let subtleInk = Color(red: 0.58, green: 0.51, blue: 0.43)
    static let accent = Color(red: 0.56, green: 0.43, blue: 0.29)
    static let accentSoft = Color(red: 0.93, green: 0.88, blue: 0.80)
    static let highlight = Color(red: 0.74, green: 0.39, blue: 0.25)
    static let highlightSoft = Color(red: 0.96, green: 0.88, blue: 0.82)
    static let danger = Color(red: 0.72, green: 0.29, blue: 0.20)
    static let success = Color(red: 0.38, green: 0.54, blue: 0.36)
    static let ambientBlue = Color(red: 0.90, green: 0.84, blue: 0.76)
    static let ambientMint = Color(red: 0.88, green: 0.80, blue: 0.69)
    static let ambientSand = Color(red: 0.94, green: 0.89, blue: 0.80)

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.96, blue: 0.92),
            Color(red: 0.96, green: 0.93, blue: 0.88),
            Color(red: 0.94, green: 0.90, blue: 0.84),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.39, green: 0.31, blue: 0.24),
            Color(red: 0.27, green: 0.21, blue: 0.16),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardShadow = Color.black.opacity(0.08)
    static let glassShadow = Color.black.opacity(0.10)
}
