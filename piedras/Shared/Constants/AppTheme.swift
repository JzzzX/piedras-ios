import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let backgroundSecondary = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let surface = Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.80)
    static let surfaceElevated = Color(red: 1.00, green: 0.99, blue: 0.98).opacity(0.92)
    static let border = Color.white.opacity(0.70)
    static let ink = Color(red: 0.18, green: 0.16, blue: 0.14)
    static let mutedInk = Color(red: 0.37, green: 0.31, blue: 0.25)
    static let subtleInk = Color(red: 0.56, green: 0.49, blue: 0.40)
    static let accent = Color(red: 0.48, green: 0.40, blue: 0.28)
    static let accentSoft = Color(red: 0.94, green: 0.90, blue: 0.84)
    static let highlight = Color(red: 0.70, green: 0.39, blue: 0.24)
    static let highlightSoft = Color(red: 0.97, green: 0.89, blue: 0.83)
    static let danger = Color(red: 0.72, green: 0.29, blue: 0.20)
    static let success = Color(red: 0.38, green: 0.54, blue: 0.36)
    static let ambientBlue = Color(red: 0.95, green: 0.88, blue: 0.76)
    static let ambientMint = Color(red: 0.94, green: 0.89, blue: 0.78)
    static let ambientSand = Color(red: 0.98, green: 0.94, blue: 0.84)

    static let homeCard = Color(red: 0.997, green: 0.992, blue: 0.984)
    static let homeCardBorder = Color.white.opacity(0.92)
    static let homeCardShadow = Color(red: 0.36, green: 0.28, blue: 0.19).opacity(0.12)

    static let documentBackground = Color(red: 0.982, green: 0.974, blue: 0.955)
    static let documentPaper = Color(red: 0.998, green: 0.996, blue: 0.992)
    static let documentPaperSecondary = Color(red: 0.987, green: 0.980, blue: 0.966)
    static let documentHairline = Color(red: 0.88, green: 0.84, blue: 0.78)
    static let documentOlive = Color(red: 0.33, green: 0.37, blue: 0.30)
    static let documentShadow = Color.black.opacity(0.06)

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.99, green: 0.98, blue: 0.95),
            Color(red: 0.98, green: 0.96, blue: 0.92),
            Color(red: 0.97, green: 0.94, blue: 0.89),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let documentGradient = LinearGradient(
        colors: [
            Color(red: 0.985, green: 0.978, blue: 0.962),
            Color(red: 0.978, green: 0.970, blue: 0.951),
            Color(red: 0.970, green: 0.962, blue: 0.942),
        ],
        startPoint: .top,
        endPoint: .bottom
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
