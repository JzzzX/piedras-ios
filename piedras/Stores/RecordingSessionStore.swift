import Foundation
import Observation

enum RecordingPhase: String {
    case idle
    case starting
    case recording
    case paused
    case stopping
}

enum ASRConnectionState: String {
    case idle
    case connecting
    case connected
    case degraded
    case disconnected
}

enum RecordingInputMode: String {
    case microphone

    var label: String {
        switch self {
        case .microphone:
            return "Mic"
        }
    }
}

@MainActor
@Observable
final class RecordingSessionStore {
    var meetingID: String?
    var phase: RecordingPhase = .idle
    var inputMode: RecordingInputMode = .microphone
    var durationSeconds = 0
    var audioLevel: Double = 0
    var waveformSamples: [Double] = Array(repeating: 0, count: 24)
    var currentPartial = ""
    var asrState: ASRConnectionState = .idle
    var isAppInBackground = false
    var infoBanner: String?
    var errorBanner: String?
    var audioCaptureState = "待机"
    var lastASRTransportMessage = "等待连接"
    var capturedPCMChunks = 0
    var capturedPCMBytes = 0
    var sentPCMChunks = 0
    var sentPCMBytes = 0

    func reset() {
        meetingID = nil
        phase = .idle
        inputMode = .microphone
        durationSeconds = 0
        audioLevel = 0
        waveformSamples = Array(repeating: 0, count: 24)
        currentPartial = ""
        asrState = .idle
        isAppInBackground = false
        infoBanner = nil
        errorBanner = nil
        audioCaptureState = "待机"
        lastASRTransportMessage = "等待连接"
        capturedPCMChunks = 0
        capturedPCMBytes = 0
        sentPCMChunks = 0
        sentPCMBytes = 0
    }

    func pushAudioLevelSample(_ sample: Double) {
        let clamped = max(0, min(sample, 1))
        audioLevel = clamped
        waveformSamples.append(clamped)
        if waveformSamples.count > 24 {
            waveformSamples.removeFirst(waveformSamples.count - 24)
        }
    }

    func beginSession(inputMode: RecordingInputMode = .microphone) {
        self.inputMode = inputMode
        audioCaptureState = "准备录音"
        lastASRTransportMessage = "等待连接"
        capturedPCMChunks = 0
        capturedPCMBytes = 0
        sentPCMChunks = 0
        sentPCMBytes = 0
        currentPartial = ""
        errorBanner = nil
    }

    func registerCapturedPCM(bytes: Int) {
        guard bytes > 0 else { return }
        capturedPCMChunks += 1
        capturedPCMBytes += bytes
    }

    func registerSentPCM(bytes: Int) {
        guard bytes > 0 else { return }
        sentPCMChunks += 1
        sentPCMBytes += bytes
    }
}
