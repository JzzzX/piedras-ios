import Foundation
import Observation

enum RecordingPhase: String {
    case idle
    case starting
    case recording
    case paused
    case stopping
}

enum RecordingPauseReason: String {
    case user
    case systemInterruption
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
    case fileMix

    var label: String {
        switch self {
        case .microphone:
            return "Mic"
        case .fileMix:
            return "Mix"
        }
    }
}

enum BackgroundTranscriptionStatus: String {
    case inactive
    case chunking
    case flushing
    case failedNeedsRepair
}

@MainActor
@Observable
final class RecordingSessionStore {
    var meetingID: String?
    var phase: RecordingPhase = .idle
    var pauseReason: RecordingPauseReason?
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
    var sourceAudioDisplayName: String?
    var sourceAudioCurrentTime: TimeInterval = 0
    var sourceAudioDuration: TimeInterval = 0
    var isSourceAudioPlaying = false
    var backgroundTranscriptionStatus: BackgroundTranscriptionStatus = .inactive
    var backgroundChunkStartTimeMS: Double?
    var backgroundChunkBufferedDurationMS: Double = 0
    var backgroundChunkFailureNeedsRepair = false
    var foregroundTranscriptGapStartTimeMS: Double?
    var backgroundTranscriptGapStartTimeMS: Double?
    var backgroundTranscriptGapEndTimeMS: Double?
    var isBackfillingBackgroundTranscript = false
    var needsTranscriptRepairAfterStop: Bool {
        hasForegroundTranscriptGap || backgroundChunkFailureNeedsRepair
    }

    func reset() {
        meetingID = nil
        phase = .idle
        pauseReason = nil
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
        sourceAudioDisplayName = nil
        sourceAudioCurrentTime = 0
        sourceAudioDuration = 0
        isSourceAudioPlaying = false
        backgroundTranscriptionStatus = .inactive
        backgroundChunkStartTimeMS = nil
        backgroundChunkBufferedDurationMS = 0
        backgroundChunkFailureNeedsRepair = false
        foregroundTranscriptGapStartTimeMS = nil
        backgroundTranscriptGapStartTimeMS = nil
        backgroundTranscriptGapEndTimeMS = nil
        isBackfillingBackgroundTranscript = false
    }

    func pushAudioLevelSample(_ sample: Double) {
        let clamped = max(0, min(sample, 1))
        audioLevel = clamped
        waveformSamples.append(clamped)
        if waveformSamples.count > 24 {
            waveformSamples.removeFirst(waveformSamples.count - 24)
        }
    }

    func beginSession(
        inputMode: RecordingInputMode = .microphone,
        sourceAudioDisplayName: String? = nil,
        sourceAudioDuration: TimeInterval = 0
    ) {
        self.inputMode = inputMode
        audioCaptureState = "准备录音"
        lastASRTransportMessage = "等待连接"
        capturedPCMChunks = 0
        capturedPCMBytes = 0
        sentPCMChunks = 0
        sentPCMBytes = 0
        currentPartial = ""
        errorBanner = nil
        self.sourceAudioDisplayName = sourceAudioDisplayName
        self.sourceAudioCurrentTime = 0
        self.sourceAudioDuration = sourceAudioDuration
        isSourceAudioPlaying = false
        pauseReason = nil
        backgroundTranscriptionStatus = .inactive
        backgroundChunkStartTimeMS = nil
        backgroundChunkBufferedDurationMS = 0
        backgroundChunkFailureNeedsRepair = false
        foregroundTranscriptGapStartTimeMS = nil
        backgroundTranscriptGapStartTimeMS = nil
        backgroundTranscriptGapEndTimeMS = nil
        isBackfillingBackgroundTranscript = false
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

    func updateSourceAudioPlayback(currentTime: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        sourceAudioCurrentTime = max(0, currentTime)
        sourceAudioDuration = max(0, duration)
        isSourceAudioPlaying = isPlaying
    }

    var hasForegroundTranscriptGap: Bool {
        foregroundTranscriptGapStartTimeMS != nil
    }

    func markTranscriptCoverageGap(at startTimeMS: Double? = nil) {
        let normalizedStartTimeMS = max(0, startTimeMS ?? 0)
        if let existingStartTimeMS = foregroundTranscriptGapStartTimeMS {
            foregroundTranscriptGapStartTimeMS = min(existingStartTimeMS, normalizedStartTimeMS)
        } else {
            foregroundTranscriptGapStartTimeMS = normalizedStartTimeMS
        }
    }

    func resolveTranscriptCoverageGap(through coveredEndTimeMS: Double) {
        guard let gapStartTimeMS = foregroundTranscriptGapStartTimeMS else { return }
        guard coveredEndTimeMS >= gapStartTimeMS else { return }
        foregroundTranscriptGapStartTimeMS = nil
    }

    func clearTranscriptCoverageGap() {
        foregroundTranscriptGapStartTimeMS = nil
    }

    var isBackgroundChunkingActive: Bool {
        switch backgroundTranscriptionStatus {
        case .chunking, .flushing:
            return true
        case .inactive, .failedNeedsRepair:
            return false
        }
    }

    func beginBackgroundChunking(at startTimeMS: Double) {
        guard !isBackgroundChunkingActive else { return }
        backgroundTranscriptionStatus = .chunking
        backgroundChunkStartTimeMS = max(0, startTimeMS)
        backgroundChunkBufferedDurationMS = 0
        backgroundChunkFailureNeedsRepair = false
    }

    func markBackgroundChunkBufferDuration(_ durationMS: Double) {
        backgroundChunkBufferedDurationMS = max(0, durationMS)
    }

    func markBackgroundChunkFlushInProgress() {
        guard backgroundTranscriptionStatus != .failedNeedsRepair else { return }
        backgroundTranscriptionStatus = .flushing
    }

    func markBackgroundChunkReadyForMore() {
        guard backgroundTranscriptionStatus != .failedNeedsRepair else { return }
        backgroundTranscriptionStatus = .chunking
    }

    func markBackgroundChunkFailureNeedsRepair() {
        backgroundTranscriptionStatus = .failedNeedsRepair
        backgroundChunkFailureNeedsRepair = true
        backgroundChunkStartTimeMS = nil
        backgroundChunkBufferedDurationMS = 0
    }

    func deactivateBackgroundChunking() {
        backgroundTranscriptionStatus = .inactive
        backgroundChunkStartTimeMS = nil
        backgroundChunkBufferedDurationMS = 0
    }

    func clearBackgroundChunkingState() {
        deactivateBackgroundChunking()
        backgroundChunkFailureNeedsRepair = false
    }

    var hasBackgroundTranscriptGap: Bool {
        backgroundTranscriptGapStartTimeMS != nil
    }

    var isCapturingBackgroundTranscriptGapAudio: Bool {
        backgroundTranscriptGapStartTimeMS != nil && backgroundTranscriptGapEndTimeMS == nil
    }

    func beginBackgroundTranscriptGap(at startTimeMS: Double) {
        guard backgroundTranscriptGapStartTimeMS == nil else { return }
        backgroundTranscriptGapStartTimeMS = max(0, startTimeMS)
        backgroundTranscriptGapEndTimeMS = nil
    }

    func endBackgroundTranscriptGap(at endTimeMS: Double) {
        guard let startTimeMS = backgroundTranscriptGapStartTimeMS else { return }
        backgroundTranscriptGapEndTimeMS = max(endTimeMS, startTimeMS)
    }

    func clearBackgroundTranscriptGap() {
        backgroundTranscriptGapStartTimeMS = nil
        backgroundTranscriptGapEndTimeMS = nil
        isBackfillingBackgroundTranscript = false
    }
}
