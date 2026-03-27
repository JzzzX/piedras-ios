import SwiftUI

struct HomeRecordingDockButton: View {
    let isRecording: Bool
    let action: () -> Void

    private let size: CGFloat = 58

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(isRecording ? AppTheme.highlight : AppTheme.surface)

                if isRecording {
                    activeGlyph
                } else {
                    idleGlyph
                }
            }
            .frame(width: size, height: size)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.ink, lineWidth: 2)
            )
            .retroHardShadow(x: isRecording ? 3 : 4, y: isRecording ? 3 : 4, color: Color.black.opacity(0.26))
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
        ZStack {
            MicSilhouette()
                .fill(AppTheme.ink)
                .frame(width: 28, height: 34)
                .offset(x: -4, y: 2)

            notepad
                .offset(x: 3, y: 0)

            pencil
                .offset(x: 10, y: 8)
        }
    }

    private var notepad: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(AppTheme.surface)
                .frame(width: 24, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(AppTheme.ink, lineWidth: 2.4)
                )

            VStack(spacing: 4) {
                notepadBindingRow
                    .padding(.top, 2)

                VStack(spacing: 4) {
                    noteLine(width: 14)
                    noteLine(width: 14)
                    noteLine(width: 11)
                }
                .padding(.top, 2)
            }
        }
        .rotationEffect(.degrees(7))
    }

    private var notepadBindingRow: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 1.8)
                    .frame(width: 4.4, height: 5)
            }
        }
    }

    private func noteLine(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(AppTheme.ink)
            .frame(width: width, height: 1.8)
    }

    private var pencil: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                .fill(AppTheme.ink)
                .frame(width: 22, height: 7)

            Triangle()
                .fill(AppTheme.ink)
                .frame(width: 8, height: 8)
                .offset(x: -5, y: 0.5)

            Rectangle()
                .fill(AppTheme.surface)
                .frame(width: 2.4, height: 8)
                .rotationEffect(.degrees(15))
                .offset(x: 12, y: 0)

            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .fill(AppTheme.ink)
                .frame(width: 5, height: 7)
                .offset(x: 17, y: 0)
        }
        .rotationEffect(.degrees(-48))
    }
}

private struct MicSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let capsuleWidth = rect.width * 0.54
        let capsuleHeight = rect.height * 0.62
        let capsuleX = rect.midX - capsuleWidth / 2
        let capsuleY = rect.minY

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: capsuleX, y: capsuleY, width: capsuleWidth, height: capsuleHeight),
            cornerSize: CGSize(width: capsuleWidth / 2, height: capsuleWidth / 2)
        )

        let stemWidth = rect.width * 0.16
        let stemHeight = rect.height * 0.20
        path.addRoundedRect(
            in: CGRect(
                x: rect.midX - stemWidth / 2,
                y: capsuleY + capsuleHeight - 2,
                width: stemWidth,
                height: stemHeight
            ),
            cornerSize: CGSize(width: stemWidth / 2, height: stemWidth / 2)
        )

        path.addRoundedRect(
            in: CGRect(
                x: rect.midX - rect.width * 0.33,
                y: rect.maxY - rect.height * 0.12,
                width: rect.width * 0.66,
                height: rect.height * 0.12
            ),
            cornerSize: CGSize(width: rect.height * 0.06, height: rect.height * 0.06)
        )

        var arm = Path()
        arm.move(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.42))
        arm.addCurve(
            to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.78),
            control1: CGPoint(x: rect.width * 0.12, y: rect.height * 0.58),
            control2: CGPoint(x: rect.width * 0.16, y: rect.height * 0.72)
        )
        arm.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.73))
        arm.addCurve(
            to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.44),
            control1: CGPoint(x: rect.width * 0.32, y: rect.height * 0.62),
            control2: CGPoint(x: rect.width * 0.30, y: rect.height * 0.50)
        )
        arm.closeSubpath()

        path.addPath(arm)
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
