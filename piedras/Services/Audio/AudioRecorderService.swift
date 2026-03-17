import AVFoundation
import Foundation

struct LocalAudioArtifact {
    let fileURL: URL
    let durationSeconds: Int
    let mimeType: String
}

@MainActor
final class AudioRecorderService: NSObject {
    var onProgress: ((Double, Int) -> Void)?

    private let sessionCoordinator: AudioSessionCoordinator
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingStartedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var recordingURL: URL?

    init(sessionCoordinator: AudioSessionCoordinator) {
        self.sessionCoordinator = sessionCoordinator
    }

    func startRecording(meetingID: String) async throws -> URL {
        let granted = await sessionCoordinator.requestMicrophonePermission()
        guard granted else {
            throw AudioSessionError.microphonePermissionDenied
        }

        try sessionCoordinator.configureForRecording()

        let outputURL = try makeRecordingURL(meetingID: meetingID)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioSessionError.recorderUnavailable
        }

        self.recorder = recorder
        recordingURL = outputURL
        accumulatedDuration = 0
        recordingStartedAt = .now
        startMetering()
        onProgress?(0, 0)
        return outputURL
    }

    func pauseRecording() throws {
        guard let recorder else {
            throw AudioSessionError.recorderUnavailable
        }

        guard recorder.isRecording else { return }
        recorder.pause()
        accumulatedDuration = currentDuration()
        recordingStartedAt = nil
        stopMetering()
        recorder.updateMeters()
        onProgress?(normalizedPower(from: recorder), Int(accumulatedDuration.rounded()))
    }

    func resumeRecording() throws {
        guard let recorder else {
            throw AudioSessionError.recorderUnavailable
        }

        try sessionCoordinator.configureForRecording()
        guard recorder.record() else {
            throw AudioSessionError.recorderUnavailable
        }

        recordingStartedAt = .now
        startMetering()
    }

    func stopRecording() throws -> LocalAudioArtifact {
        guard let recorder, let recordingURL else {
            throw AudioSessionError.recorderUnavailable
        }

        let finalDuration = max(Int(currentDuration().rounded()), Int(recorder.currentTime.rounded()))
        recorder.stop()
        stopMetering()
        self.recorder = nil
        self.recordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        sessionCoordinator.deactivate()

        return LocalAudioArtifact(
            fileURL: recordingURL,
            durationSeconds: finalDuration,
            mimeType: "audio/m4a"
        )
    }

    private func currentDuration() -> TimeInterval {
        accumulatedDuration + (recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder else { return }
                recorder.updateMeters()
                onProgress?(normalizedPower(from: recorder), Int(currentDuration().rounded()))
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func normalizedPower(from recorder: AVAudioRecorder) -> Double {
        let power = recorder.averagePower(forChannel: 0)
        let level = pow(10, power / 20)
        return max(0, min(Double(level), 1))
    }

    private func makeRecordingURL(meetingID: String) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent(meetingID, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("recording.m4a")
    }
}
