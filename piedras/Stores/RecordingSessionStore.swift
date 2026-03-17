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

@MainActor
@Observable
final class RecordingSessionStore {
    var meetingID: String?
    var phase: RecordingPhase = .idle
    var durationSeconds = 0
    var audioLevel: Double = 0
    var waveformSamples: [Double] = Array(repeating: 0, count: 24)
    var currentPartial = ""
    var asrState: ASRConnectionState = .idle
    var errorBanner: String?

    func reset() {
        meetingID = nil
        phase = .idle
        durationSeconds = 0
        audioLevel = 0
        waveformSamples = Array(repeating: 0, count: 24)
        currentPartial = ""
        asrState = .idle
        errorBanner = nil
    }

    func pushAudioLevelSample(_ sample: Double) {
        let clamped = max(0, min(sample, 1))
        audioLevel = clamped
        waveformSamples.append(clamped)
        if waveformSamples.count > 24 {
            waveformSamples.removeFirst(waveformSamples.count - 24)
        }
    }
}
