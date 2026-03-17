import SwiftUI
import UIKit

enum AppGlassStyle {
    case regular
    case clear
}

struct AppGlassBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.pageGradient

            Circle()
                .fill(AppTheme.ambientBlue.opacity(0.42))
                .frame(width: 320, height: 320)
                .blur(radius: 36)
                .offset(x: 110, y: -260)

            Circle()
                .fill(AppTheme.ambientMint.opacity(0.28))
                .frame(width: 260, height: 260)
                .blur(radius: 28)
                .offset(x: -120, y: -180)

            Circle()
                .fill(AppTheme.ambientSand.opacity(0.30))
                .frame(width: 280, height: 280)
                .blur(radius: 36)
                .offset(x: -80, y: 300)
        }
        .ignoresSafeArea()
    }
}

struct AppGlassSurface: View {
    var cornerRadius: CGFloat = 28
    var style: AppGlassStyle = .regular
    var borderOpacity: Double = 0.24
    var shadowOpacity: Double = 0.12

    var body: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                NativeGlassBackground(cornerRadius: cornerRadius, style: style)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(style == .clear ? .thinMaterial : .ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(style == .clear ? 0.10 : 0.16))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(borderOpacity), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(shadowOpacity), radius: 28, x: 0, y: 16)
    }
}

struct AppGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 32
    var style: AppGlassStyle = .regular
    var padding: CGFloat = 20
    var shadowOpacity: Double = 0.12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                AppGlassSurface(
                    cornerRadius: cornerRadius,
                    style: style,
                    borderOpacity: 0.28,
                    shadowOpacity: shadowOpacity
                )
            }
    }
}

struct AppGlassDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.55))
            .frame(height: 1)
            .padding(.leading, inset)
            .opacity(0.7)
    }
}

struct AppGlassCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = 44
    var prominent = false
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            if prominent {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(accessibilityLabel)
            } else {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: size, height: size)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(accessibilityLabel)
            }
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(prominent ? .white : AppTheme.ink)
                    .frame(width: size, height: size)
                    .background {
                        if prominent {
                            Circle().fill(AppTheme.ink)
                        } else {
                            AppGlassSurface(cornerRadius: size / 2, style: .regular, shadowOpacity: 0.08)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

struct AppGlassCapsuleButton<Label: View>: View {
    var prominent = false
    var minHeight: CGFloat = 52
    var fillsWidth = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(iOS 26.0, *) {
            if prominent {
                Button(action: action) {
                    label()
                        .frame(minHeight: minHeight)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: action) {
                    label()
                        .frame(minHeight: minHeight)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                }
                .buttonStyle(.glass)
            }
        } else {
            Button(action: action) {
                label()
                    .frame(minHeight: minHeight)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .background {
                        if prominent {
                            Capsule().fill(AppTheme.ink)
                        } else {
                            AppGlassSurface(cornerRadius: minHeight / 2, style: .regular, shadowOpacity: 0.08)
                                .clipShape(Capsule())
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

@available(iOS 26.0, *)
private struct NativeGlassBackground: UIViewRepresentable {
    let cornerRadius: CGFloat
    let style: AppGlassStyle

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.layer.cornerRadius = cornerRadius

        let effect = UIGlassEffect(style: style == .clear ? .clear : .regular)
        uiView.effect = effect
        uiView.backgroundColor = .clear
    }
}
