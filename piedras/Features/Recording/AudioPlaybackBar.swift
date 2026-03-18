import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loadedURL: URL?

    func togglePlayback(fileURL: URL) {
        do {
            if loadedURL != fileURL {
                try load(fileURL: fileURL)
            }

            guard let player else { return }

            if player.isPlaying {
                player.pause()
                stopTimer()
                isPlaying = false
            } else {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                player.play()
                startTimer()
                isPlaying = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seek(to newValue: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(newValue, 0), duration)
        currentTime = player.currentTime
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentTime = duration
        isPlaying = false
        stopTimer()
    }

    private func load(fileURL: URL) throws {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        loadedURL = fileURL
        duration = player.duration
        currentTime = player.currentTime
        errorMessage = nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player else { return }
                currentTime = player.currentTime
                if !player.isPlaying {
                    isPlaying = false
                    stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct AudioPlaybackBar: View {
    let filePath: String

    @State private var playbackController = AudioPlaybackController()

    var body: some View {
        let fileURL = URL(fileURLWithPath: filePath)

        VStack(alignment: .leading, spacing: 14) {
            PlaybackWaveformStrip(progress: playbackProgress)
                .frame(height: 22)

            HStack(spacing: 12) {
                Button {
                    playbackController.togglePlayback(fileURL: fileURL)
                } label: {
                    GlassIconBadge(
                        systemName: playbackController.isPlaying ? "pause.fill" : "play.fill",
                        size: 40,
                        symbolSize: 15,
                        shape: .circle
                    )
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { playbackController.currentTime },
                        set: { playbackController.seek(to: $0) }
                    ),
                    in: 0...max(playbackController.duration, 1)
                )
                .tint(AppTheme.documentOlive)

                Text("\(playbackController.currentTime.mmss) / \(playbackController.duration.mmss)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.subtleInk)
            }

            if let error = playbackController.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .padding(16)
        .background {
            PaperSurface(
                cornerRadius: 24,
                fill: AppTheme.documentPaper,
                border: AppTheme.documentHairline,
                shadowOpacity: 0.08
            )
        }
    }

    private var playbackProgress: Double {
        guard playbackController.duration > 0 else { return 0 }
        return min(max(playbackController.currentTime / playbackController.duration, 0), 1)
    }
}

private struct PlaybackWaveformStrip: View {
    let progress: Double

    private let barHeights: [CGFloat] = [5, 9, 12, 7, 15, 10, 6, 13, 18, 10, 7, 14, 9, 5, 11, 16, 8, 6, 12, 17, 8, 5, 10, 14, 7, 6, 12, 9, 5, 8]

    var body: some View {
        GeometryReader { proxy in
            let count = barHeights.count
            let step = proxy.size.width / CGFloat(max(count, 1))
            let activeCount = Int((Double(count) * progress).rounded(.down))

            HStack(alignment: .center, spacing: max(2, step * 0.22)) {
                ForEach(Array(barHeights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(index < activeCount ? AppTheme.documentOlive : AppTheme.documentHairline.opacity(0.55))
                        .frame(width: max(2, step * 0.36), height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
