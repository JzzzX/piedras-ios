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

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    playbackController.togglePlayback(fileURL: fileURL)
                } label: {
                    Label(
                        playbackController.isPlaying ? "暂停回放" : "播放录音",
                        systemImage: playbackController.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(playbackController.currentTime.mmss) / \(playbackController.duration.mmss)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { playbackController.currentTime },
                    set: { playbackController.seek(to: $0) }
                ),
                in: 0...max(playbackController.duration, 1)
            )

            if let error = playbackController.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
