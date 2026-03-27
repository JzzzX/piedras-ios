import SwiftUI

struct HomeRecordingDockButton: View {
    static let idleAssetName = "HomeRecordingDockIdleIcon"

    let isRecording: Bool
    let action: () -> Void

    private let size: CGFloat = 58

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Rectangle()
                        .fill(AppTheme.highlight)

                    activeGlyph
                } else {
                    idleGlyph
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .overlay {
                if isRecording {
                    Rectangle()
                        .stroke(AppTheme.ink, lineWidth: 2)
                }
            }
            .retroHardShadow(x: isRecording ? 3 : 0, y: isRecording ? 3 : 0, color: Color.black.opacity(0.26))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? AppStrings.current.stop : AppStrings.current.newRecording)
        .accessibilityIdentifier("NewRecordingButton")
    }

    private var activeGlyph: some View {
        VStack(spacing: 5) {
            Image(systemName: "stop.fill")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(AppTheme.surface)

            Text(AppStrings.current.stop.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(AppTheme.surface.opacity(0.92))
                .tracking(0.5)
        }
    }

    private var idleGlyph: some View {
        Image(Self.idleAssetName)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
    }
}
