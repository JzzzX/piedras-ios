import AVFoundation
import Observation
import SwiftUI

struct AudioPlaybackBar: View {
    let sourceURL: URL

    @State private var playbackController = AudioPlaybackController()

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    init(filePath: String) {
        self.sourceURL = URL(fileURLWithPath: filePath)
    }

    var body: some View {
        TranscriptAudioControlBar(
            sourceURL: sourceURL,
            playbackController: playbackController,
            onPlaybackIntent: {}
        )
        .id(AppStrings.currentLanguage)
    }
}

@MainActor
@Observable
final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate {
    var isPreparing = false
    var isPlaying = false
    var isScrubbing = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Double = 1.0 {
        didSet {
            let normalizedRate = min(max(playbackRate, 0.75), 2.0)
            if normalizedRate != playbackRate {
                playbackRate = normalizedRate
                return
            }

            player?.enableRate = true
            player?.rate = Float(playbackRate)
        }
    }
    var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loadedSourceIdentifier: String?
    private var loadedFileURL: URL?

    func prepare(sourceURL: URL) async {
        do {
            try await prepareIfNeeded(sourceURL: sourceURL)
        } catch {
            errorMessage = UserVisibleMediaErrorFormatter.playbackFailureMessage(for: error)
        }
    }

    func togglePlayback(sourceURL: URL) async {
        do {
            try await prepareIfNeeded(sourceURL: sourceURL)
            guard let player else { return }

            if player.isPlaying {
                pause()
            } else {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                player.enableRate = true
                player.rate = Float(playbackRate)
                player.play()
                startTimer()
                isPlaying = true
                errorMessage = nil
            }
        } catch {
            errorMessage = UserVisibleMediaErrorFormatter.playbackFailureMessage(for: error)
        }
    }

    func pause() {
        player?.pause()
        stopTimer()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player = nil
        stopTimer()
        isPlaying = false
        currentTime = 0
        duration = 0
        loadedSourceIdentifier = nil
        loadedFileURL = nil
    }

    func seek(to newValue: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(newValue, 0), duration)
        currentTime = player.currentTime
    }

    func seek(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func setScrubbing(_ isScrubbing: Bool) {
        self.isScrubbing = isScrubbing
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentTime = duration
        isPlaying = false
        stopTimer()
    }

    private func prepareIfNeeded(sourceURL: URL) async throws {
        let sourceIdentifier = sourceURL.absoluteString
        if loadedSourceIdentifier == sourceIdentifier,
           player != nil,
           loadedFileURL.map({ FileManager.default.fileExists(atPath: $0.path) }) != false {
            return
        }

        isPreparing = true
        defer { isPreparing = false }

        let resolvedFileURL: URL
        if sourceURL.isFileURL {
            resolvedFileURL = sourceURL
        } else {
            resolvedFileURL = try await AudioFileResolver.resolveFileURL(
                localPath: nil,
                remoteURLString: sourceIdentifier
            )
        }

        try load(fileURL: resolvedFileURL, sourceIdentifier: sourceIdentifier)
    }

    private func load(fileURL: URL, sourceIdentifier: String) throws {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.delegate = self
        player.enableRate = true
        player.rate = Float(playbackRate)
        player.prepareToPlay()

        self.player = player
        self.loadedFileURL = fileURL
        self.loadedSourceIdentifier = sourceIdentifier
        self.duration = player.duration
        self.currentTime = player.currentTime
        self.errorMessage = nil
        self.isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player else { return }
                if !isScrubbing {
                    currentTime = player.currentTime
                }

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

struct TranscriptAudioControlBar: View {
    let sourceURL: URL
    var playbackController: AudioPlaybackController
    var isRetranscribing = false
    let onPlaybackIntent: () -> Void

    @State private var didPrepare = false

    var body: some View {
        @Bindable var playbackController = playbackController

        VStack(spacing: 0) {
            RetroTitleBar(label: AppStrings.current.playback)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        onPlaybackIntent()
                        Task {
                            await playbackController.togglePlayback(sourceURL: sourceURL)
                        }
                    } label: {
                        ZStack {
                            Rectangle()
                                .fill(AppTheme.primaryActionFill)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Rectangle()
                                        .stroke(AppTheme.brandInk, lineWidth: AppTheme.retroBorderWidth)
                                )

                            if playbackController.isPreparing {
                                ProgressView()
                                    .tint(AppTheme.primaryActionForeground)
                            } else {
                                Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppTheme.primaryActionForeground)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(playbackController.isPreparing || isRetranscribing)
                    .accessibilityIdentifier("TranscriptPlaybackToggleButton")

                    Text("\(playbackController.currentTime.mmss) / \(playbackController.duration.mmss)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.subtleInk)
                        .accessibilityIdentifier("TranscriptPlaybackTimeLabel")

                    Spacer(minLength: 0)

                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button(rateLabel(rate), systemImage: playbackController.playbackRate == rate ? "checkmark" : "") {
                                playbackController.playbackRate = rate
                            }
                        }
                    } label: {
                        Text(rateLabel(playbackController.playbackRate))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.brandInk)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(AppTheme.selectedChromeFill)
                            .overlay(
                                Rectangle()
                                    .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.retroBorderWidth)
                            )
                    }
                    .disabled(isRetranscribing)
                    .accessibilityIdentifier("TranscriptPlaybackSpeedButton")
                }

                HStack(spacing: 12) {
                    jumpButton(systemName: "gobackward.15") {
                        onPlaybackIntent()
                        playbackController.seek(by: -15)
                    }

                    Slider(
                        value: Binding(
                            get: { playbackController.currentTime },
                            set: { playbackController.seek(to: $0) }
                        ),
                        in: 0...max(playbackController.duration, 1),
                        onEditingChanged: { isEditing in
                            playbackController.setScrubbing(isEditing)
                            if !isEditing {
                                onPlaybackIntent()
                            }
                        }
                    )
                    .tint(AppTheme.primaryActionFill)
                    .disabled(playbackController.isPreparing || isRetranscribing)
                    .accessibilityIdentifier("TranscriptPlaybackSlider")

                    jumpButton(systemName: "goforward.15") {
                        onPlaybackIntent()
                        playbackController.seek(by: 15)
                    }
                }

                if let error = playbackController.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
        .task(id: sourceURL.absoluteString) {
            guard !didPrepare else { return }
            didPrepare = true
            await playbackController.prepare(sourceURL: sourceURL)
        }
        .onChange(of: sourceURL.absoluteString, initial: false) { _, _ in
            didPrepare = false
        }
    }

    private func jumpButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.brandInk)
                .frame(width: 34, height: 34)
                .background(AppTheme.selectedChromeFill)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.retroBorderWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(isRetranscribing || playbackController.isPreparing)
    }

    private func rateLabel(_ rate: Double) -> String {
        switch rate {
        case 0.75:
            return "0.75x"
        case 1.0:
            return "1.0x"
        case 1.25:
            return "1.25x"
        case 1.5:
            return "1.5x"
        case 2.0:
            return "2.0x"
        default:
            return String(format: "%.2fx", rate)
        }
    }
}
