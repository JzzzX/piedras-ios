import SwiftUI

struct WaveformView: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let count = max(samples.count, 1)
            let barWidth = max(width / CGFloat(count * 2), 3)

            HStack(alignment: .center, spacing: barWidth) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(sample > 0.08 ? AppTheme.highlight : AppTheme.border.opacity(0.8))
                        .frame(width: barWidth, height: max(6, height * sample))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
