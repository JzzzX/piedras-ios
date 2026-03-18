import SwiftUI
import UIKit

enum AppTheme {
    static var background: Color { color(light: 0xF6F5F2, dark: 0x14100D) }
    static var backgroundSecondary: Color { color(light: 0xFBFAF7, dark: 0x1A1511) }
    static var surface: Color { rgba(light: (0xFF, 0xFF, 0xFD, 0.82), dark: (0x28, 0x22, 0x1C, 0.72)) }
    static var surfaceElevated: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.92), dark: (0x34, 0x2C, 0x25, 0.84)) }
    static var border: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.80), dark: (0xFF, 0xFF, 0xFF, 0.10)) }
    static var ink: Color { color(light: 0x2E2721, dark: 0xF2E7DA) }
    static var mutedInk: Color { color(light: 0x58514A, dark: 0xD2C0AF) }
    static var subtleInk: Color { color(light: 0x89817A, dark: 0xA28F7C) }
    static var accent: Color { color(light: 0x69625A, dark: 0xD3BEA3) }
    static var accentSoft: Color { color(light: 0xEEEAE3, dark: 0x352D26) }
    static var highlight: Color { color(light: 0x9A7759, dark: 0xD08A5D) }
    static var highlightSoft: Color { color(light: 0xF5EEE6, dark: 0x443126) }
    static var danger: Color { color(light: 0xB84E35, dark: 0xDE8A6C) }
    static var success: Color { color(light: 0x5F824D, dark: 0x89AA73) }
    static var ambientBlue: Color { color(light: 0xECEAE4, dark: 0x3A322C) }
    static var ambientMint: Color { color(light: 0xF1F0EB, dark: 0x2E2924) }
    static var ambientSand: Color { color(light: 0xF7F5EF, dark: 0x463C32) }

    static var homeCard: Color { color(light: 0xFFFDFC, dark: 0x1E1814) }
    static var homeCardBorder: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.92), dark: (0xFF, 0xFF, 0xFF, 0.08)) }
    static var homeCardShadow: Color { rgba(light: (0x29, 0x24, 0x1F, 0.09), dark: (0x00, 0x00, 0x00, 0.26)) }

    static var documentBackground: Color { color(light: 0xF7F6F2, dark: 0x17120F) }
    static var documentPaper: Color { color(light: 0xFFFEFC, dark: 0x221B16) }
    static var documentPaperSecondary: Color { color(light: 0xFAF8F4, dark: 0x2B241D) }
    static var documentHairline: Color { color(light: 0xD8D3CA, dark: 0x4A3F35) }
    static var documentOlive: Color { color(light: 0x59634F, dark: 0xB9C2A7) }
    static var documentShadow: Color { rgba(light: (0x00, 0x00, 0x00, 0.05), dark: (0x00, 0x00, 0x00, 0.28)) }

    static var glassStroke: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.58), dark: (0xFF, 0xFF, 0xFF, 0.14)) }
    static var glassHighlight: Color { rgba(light: (0xFF, 0xFF, 0xFF, 0.52), dark: (0xFF, 0xFF, 0xFF, 0.09)) }
    static var glassTint: Color { rgba(light: (0xFF, 0xFF, 0xFC, 0.20), dark: (0x4C, 0x3F, 0x34, 0.22)) }
    static var glassShadow: Color { rgba(light: (0x00, 0x00, 0x00, 0.10), dark: (0x00, 0x00, 0x00, 0.22)) }
    static var glassIconStart: Color { color(light: 0xFFFEFA, dark: 0x3A3028) }
    static var glassIconEnd: Color { color(light: 0xF2EEE7, dark: 0x26201B) }

    static var pageGradient: LinearGradient {
        LinearGradient(
            colors: [
                color(light: 0xFBFAF7, dark: 0x17120F),
                color(light: 0xF7F6F2, dark: 0x1B1511),
                color(light: 0xF2F1ED, dark: 0x201915),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var documentGradient: LinearGradient {
        LinearGradient(
            colors: [
                color(light: 0xFBFAF7, dark: 0x191310),
                color(light: 0xF7F5F1, dark: 0x1C1612),
                color(light: 0xF2F0EB, dark: 0x231C17),
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
    static let editorialBodyLineSpacing: CGFloat = 8
    static let editorialSectionSpacing: CGFloat = 18
    static let editorialParagraphSpacing: CGFloat = 16

    static func editorialFont(size: CGFloat) -> Font {
        Font(editorialUIFont(size: size, weight: .regular))
    }

    static func editorialEmphasisFont(size: CGFloat) -> Font {
        Font(editorialUIFont(size: size, weight: .semibold))
    }

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

    static func editorialUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let candidateNames: [String]

        if weight.rawValue >= UIFont.Weight.semibold.rawValue {
            candidateNames = ["Songti SC Bold", "Songti SC Semibold", "Songti SC"]
        } else if weight.rawValue <= UIFont.Weight.light.rawValue {
            candidateNames = ["Songti SC Light", "Songti SC", "STSongti-SC-Light"]
        } else {
            candidateNames = ["Songti SC", "Songti SC Regular", "STSongti-SC-Regular"]
        }

        for name in candidateNames {
            if let font = UIFont(name: name, size: size) {
                return font
            }
        }

        return UIFont.systemFont(ofSize: size, weight: weight)
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
