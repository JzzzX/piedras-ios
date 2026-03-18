import SwiftUI
import UIKit

enum AppTheme {
    static var background: Color { color(light: 0xFAF7F0, dark: 0x14100D) }
    static var backgroundSecondary: Color { color(light: 0xFEFBF5, dark: 0x1A1511) }
    static var surface: Color { rgba(light: (0xFE, 0xFB, 0xF6, 0.82), dark: (0x28, 0x22, 0x1C, 0.72)) }
    static var surfaceElevated: Color { rgba(light: (0xFF, 0xFC, 0xF8, 0.92), dark: (0x34, 0x2C, 0x25, 0.84)) }
    static var border: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.72), dark: (0xFF, 0xFF, 0xFF, 0.10)) }
    static var ink: Color { color(light: 0x2E2721, dark: 0xF2E7DA) }
    static var mutedInk: Color { color(light: 0x5D5145, dark: 0xD2C0AF) }
    static var subtleInk: Color { color(light: 0x8A7A68, dark: 0xA28F7C) }
    static var accent: Color { color(light: 0x725E48, dark: 0xD3BEA3) }
    static var accentSoft: Color { color(light: 0xEFE5D7, dark: 0x352D26) }
    static var highlight: Color { color(light: 0xB96A3B, dark: 0xD08A5D) }
    static var highlightSoft: Color { color(light: 0xF7E3D4, dark: 0x443126) }
    static var danger: Color { color(light: 0xB84E35, dark: 0xDE8A6C) }
    static var success: Color { color(light: 0x5F824D, dark: 0x89AA73) }
    static var ambientBlue: Color { color(light: 0xF2DDC1, dark: 0x3A322C) }
    static var ambientMint: Color { color(light: 0xEFE1C8, dark: 0x2E2924) }
    static var ambientSand: Color { color(light: 0xF9EED8, dark: 0x463C32) }

    static var homeCard: Color { color(light: 0xFFFCF8, dark: 0x1E1814) }
    static var homeCardBorder: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.92), dark: (0xFF, 0xFF, 0xFF, 0.08)) }
    static var homeCardShadow: Color { rgba(light: (0x3F, 0x31, 0x24, 0.12), dark: (0x00, 0x00, 0x00, 0.26)) }

    static var documentBackground: Color { color(light: 0xFBF6EE, dark: 0x17120F) }
    static var documentPaper: Color { color(light: 0xFFFDF9, dark: 0x221B16) }
    static var documentPaperSecondary: Color { color(light: 0xF9F3E9, dark: 0x2B241D) }
    static var documentHairline: Color { color(light: 0xD8CDBF, dark: 0x4A3F35) }
    static var documentOlive: Color { color(light: 0x59634F, dark: 0xB9C2A7) }
    static var documentShadow: Color { rgba(light: (0x00, 0x00, 0x00, 0.06), dark: (0x00, 0x00, 0x00, 0.28)) }

    static var glassStroke: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.58), dark: (0xFF, 0xFF, 0xFF, 0.14)) }
    static var glassHighlight: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.52), dark: (0xFF, 0xFF, 0xFF, 0.09)) }
    static var glassTint: Color { rgba(light: (0xFF, 0xFA, 0xF3, 0.22), dark: (0x4C, 0x3F, 0x34, 0.22)) }
    static var glassShadow: Color { rgba(light: (0x00, 0x00, 0x00, 0.10), dark: (0x00, 0x00, 0x00, 0.22)) }
    static var glassIconStart: Color { color(light: 0xFFF9F0, dark: 0x3A3028) }
    static var glassIconEnd: Color { color(light: 0xF2E4D0, dark: 0x26201B) }

    static var pageGradient: LinearGradient {
        LinearGradient(
            colors: [
                color(light: 0xFEFBF5, dark: 0x17120F),
                color(light: 0xFAF3E8, dark: 0x1B1511),
                color(light: 0xF6ECE0, dark: 0x201915),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var documentGradient: LinearGradient {
        LinearGradient(
            colors: [
                color(light: 0xFCF7EF, dark: 0x191310),
                color(light: 0xF7F0E5, dark: 0x1C1612),
                color(light: 0xF2EAE0, dark: 0x231C17),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                color(light: 0x665240, dark: 0x7B6653),
                color(light: 0x3B3026, dark: 0x41372E),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardShadow: Color { rgba(light: (0x00, 0x00, 0x00, 0.08), dark: (0x00, 0x00, 0x00, 0.26)) }

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }

    private static func rgba(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) -> Color {
        Color(
            uiColor: UIColor { traits in
                let value = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat(value.0) / 255,
                    green: CGFloat(value.1) / 255,
                    blue: CGFloat(value.2) / 255,
                    alpha: value.3
                )
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
