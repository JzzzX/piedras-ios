import AVFoundation
import Foundation

struct LocalAudioArtifact {
    let fileURL: URL
    let durationSeconds: Int
    let mimeType: String
}

struct SourceAudioAsset {
    let fileURL: URL
    let displayName: String
}

struct RecordingStartArtifact {
    let fileURL: URL
    let mimeType: String
    let inputMode: RecordingInputMode
    let sourceAudioLocalPath: String?
    let sourceAudioDisplayName: String?
    let sourceAudioDurationSeconds: Int
}

struct RecordingSnapshotArtifact {
    let fileURL: URL
    let mimeType: String
    let durationSeconds: Int
}

enum AudioRecorderForegroundRecoveryResult: Equatable {
    case healthy
    case recovered
    case needsUserResume(String)
}

@MainActor
protocol AudioRecorderServicing: AnyObject {
    var onProgress: ((Double, Int) -> Void)? { get set }
    var onPCMData: ((Data) -> Void)? { get set }
    var onCaptureStateChange: ((String) -> Void)? { get set }
    var onSourcePlaybackUpdate: ((TimeInterval, TimeInterval, Bool, String?) -> Void)? { get set }
    var onLifecycleEvent: ((AudioSessionLifecycleEvent) -> Void)? { get set }

    func startRecording(
        meetingID: String,
        sourceAudio: SourceAudioAsset?
    ) async throws -> RecordingStartArtifact
    func pauseRecording() throws
    func resumeRecording() throws
    func stopRecording() throws -> LocalAudioArtifact
    func toggleSourceAudioPlayback() throws
    func reconcileForegroundRecording() -> AudioRecorderForegroundRecoveryResult
    func currentRecordingDurationSeconds() -> Int
    func makeRecordingSnapshot() throws -> RecordingSnapshotArtifact?
}

@MainActor
final class AudioRecorderService: NSObject, AudioRecorderServicing {
    var onProgress: ((Double, Int) -> Void)?
    var onPCMData: ((Data) -> Void)?
    var onCaptureStateChange: ((String) -> Void)?
    var onSourcePlaybackUpdate: ((TimeInterval, TimeInterval, Bool, String?) -> Void)?
    var onLifecycleEvent: ((AudioSessionLifecycleEvent) -> Void)?

    private let sessionCoordinator: AudioSessionCoordinator
    private var recorder: AVAudioRecorder?
    private let audioEngine = AVAudioEngine()
    private var meterTimer: Timer?
    private var sourceProgressTimer: Timer?
    private var recordingStartedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var recordingURL: URL?
    private var captureMode: RecordingInputMode = .microphone
    private var isInputTapInstalled = false
    private var isRecordingMixerTapInstalled = false
    private var recordingMixer: AVAudioMixerNode?
    private var playerNode: AVAudioPlayerNode?
    private var mixedRecordingFile: AVAudioFile?
    private var sourceAudioFile: AVAudioFile?
    private var sourceAudioLocalURL: URL?
    private var sourceAudioDisplayName: String?
    private var sourceAudioFramePosition: AVAudioFramePosition = 0
    private var sourceAudioScheduledStartFrame: AVAudioFramePosition = 0
    private var sourceAudioTotalFrames: AVAudioFramePosition = 0
    private var sourceAudioDuration: TimeInterval = 0
    private var isSourceAudioPlaying = false
    private var shouldResumeSourceAfterRecordingPause = false
    private var sourcePlaybackGeneration = 0

    init(sessionCoordinator: AudioSessionCoordinator) {
        self.sessionCoordinator = sessionCoordinator
        super.init()
        self.sessionCoordinator.onLifecycleEvent = { [weak self] event in
            self?.handleSessionLifecycleEvent(event)
        }
    }

    func startRecording(
        meetingID: String,
        sourceAudio: SourceAudioAsset? = nil
    ) async throws -> RecordingStartArtifact {
        let granted = await sessionCoordinator.requestMicrophonePermission()
        guard granted else {
            throw AudioSessionError.microphonePermissionDenied
        }

        resetRuntimeState()

        if let sourceAudio {
            return try startMixedRecording(meetingID: meetingID, sourceAudio: sourceAudio)
        }

        return try startMicrophoneRecording(meetingID: meetingID)
    }

    func pauseRecording() throws {
        switch captureMode {
        case .microphone:
            try pauseMicrophoneRecording()
        case .fileMix:
            try pauseMixedRecording()
        }
    }

    func resumeRecording() throws {
        switch captureMode {
        case .microphone:
            try resumeMicrophoneRecording()
        case .fileMix:
            try resumeMixedRecording()
        }
    }

    func stopRecording() throws -> LocalAudioArtifact {
        switch captureMode {
        case .microphone:
            return try stopMicrophoneRecording()
        case .fileMix:
            return try stopMixedRecording()
        }
    }

    func toggleSourceAudioPlayback() throws {
        guard captureMode == .fileMix else { return }

        if isSourceAudioPlaying {
            pauseSourceAudioPlayback()
        } else {
            try playSourceAudioFromCurrentPosition(resetIfNeeded: true)
        }
    }

    func reconcileForegroundRecording() -> AudioRecorderForegroundRecoveryResult {
        switch captureMode {
        case .microphone:
            return reconcileMicrophoneRecordingAfterForeground()
        case .fileMix:
            return reconcileMixedRecordingAfterForeground()
        }
    }

    func currentRecordingDurationSeconds() -> Int {
        switch captureMode {
        case .microphone:
            let recorderDuration = recorder.map { Int($0.currentTime.rounded()) } ?? 0
            return max(Int(currentDuration().rounded()), recorderDuration)
        case .fileMix:
            return Int(currentDuration().rounded())
        }
    }

    func makeRecordingSnapshot() throws -> RecordingSnapshotArtifact? {
        guard let recordingURL else { return nil }

        let ext = recordingURL.pathExtension.isEmpty
            ? (captureMode == .microphone ? "m4a" : "wav")
            : recordingURL.pathExtension
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("coco-interview-recording-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: snapshotDirectory,
            withIntermediateDirectories: true
        )

        let snapshotURL = snapshotDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        let data = try Data(contentsOf: recordingURL)
        try data.write(to: snapshotURL, options: .atomic)

        return RecordingSnapshotArtifact(
            fileURL: snapshotURL,
            mimeType: captureMode == .microphone ? "audio/m4a" : "audio/wav",
            durationSeconds: currentRecordingDurationSeconds()
        )
    }

    private func startMicrophoneRecording(meetingID: String) throws -> RecordingStartArtifact {
        try sessionCoordinator.configureForRecording()

        let outputURL = try makeRecordingURL(meetingID: meetingID, filename: "recording.m4a")
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
        captureMode = .microphone
        recordingURL = outputURL
        accumulatedDuration = 0
        recordingStartedAt = .now
        onCaptureStateChange?("麦克风已启动")
        try startPCMStreaming()
        startMetering()
        onProgress?(0, 0)

        return RecordingStartArtifact(
            fileURL: outputURL,
            mimeType: "audio/m4a",
            inputMode: .microphone,
            sourceAudioLocalPath: nil,
            sourceAudioDisplayName: nil,
            sourceAudioDurationSeconds: 0
        )
    }

    private func startMixedRecording(
        meetingID: String,
        sourceAudio: SourceAudioAsset
    ) throws -> RecordingStartArtifact {
        try sessionCoordinator.configureForRecording(allowsFilePlayback: true)

        let meetingDirectoryURL = try makeMeetingDirectoryURL(meetingID: meetingID)
        let persistedSourceURL = try persistSourceAudio(sourceAudio, in: meetingDirectoryURL)
        let sourceFile = try AVAudioFile(forReading: persistedSourceURL)

        let outputURL = try makeRecordingURL(meetingID: meetingID, filename: "recording.wav")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        captureMode = .fileMix
        recordingURL = outputURL
        accumulatedDuration = 0
        recordingStartedAt = .now
        sourceAudioLocalURL = persistedSourceURL
        sourceAudioFile = sourceFile
        sourceAudioDisplayName = sourceAudio.displayName
        sourceAudioFramePosition = 0
        sourceAudioScheduledStartFrame = 0
        sourceAudioTotalFrames = sourceFile.length
        sourceAudioDuration = sourceFile.processingFormat.sampleRate > 0
            ? Double(sourceFile.length) / sourceFile.processingFormat.sampleRate
            : 0
        shouldResumeSourceAfterRecordingPause = false

        let playerNode = AVAudioPlayerNode()
        let recordingMixer = AVAudioMixerNode()
        self.playerNode = playerNode
        self.recordingMixer = recordingMixer
        audioEngine.attach(playerNode)
        audioEngine.attach(recordingMixer)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        audioEngine.connect(inputNode, to: recordingMixer, format: inputFormat)
        audioEngine.connect(
            playerNode,
            to: [
                AVAudioConnectionPoint(node: recordingMixer, bus: 0),
                AVAudioConnectionPoint(node: audioEngine.mainMixerNode, bus: 0),
            ],
            fromBus: 0,
            format: sourceFile.processingFormat
        )

        let mixFormat = recordingMixer.outputFormat(forBus: 0)
        mixedRecordingFile = try AVAudioFile(forWriting: outputURL, settings: mixFormat.settings)
        installRecordingMixerTap(format: mixFormat)

        audioEngine.prepare()
        try audioEngine.start()
        try playSourceAudioFromCurrentPosition()
        onProgress?(0, 0)
        onCaptureStateChange?("音频文件+麦克风已启动")

        return RecordingStartArtifact(
            fileURL: outputURL,
            mimeType: "audio/wav",
            inputMode: .fileMix,
            sourceAudioLocalPath: persistedSourceURL.path,
            sourceAudioDisplayName: sourceAudio.displayName,
            sourceAudioDurationSeconds: Int(sourceAudioDuration.rounded())
        )
    }

    private func pauseMicrophoneRecording() throws {
        guard let recorder else {
            throw AudioSessionError.recorderUnavailable
        }

        guard recorder.isRecording else { return }
        recorder.pause()
        accumulatedDuration = currentDuration()
        recordingStartedAt = nil
        audioEngine.pause()
        stopMetering()
        recorder.updateMeters()
        onCaptureStateChange?("录音已暂停")
        onProgress?(normalizedPower(from: recorder), Int(accumulatedDuration.rounded()))
    }

    private func pauseMixedRecording() throws {
        guard recordingURL != nil else {
            throw AudioSessionError.recorderUnavailable
        }

        accumulatedDuration = currentDuration()
        recordingStartedAt = nil
        shouldResumeSourceAfterRecordingPause = isSourceAudioPlaying
        pauseSourceAudioPlayback()
        audioEngine.pause()
        onCaptureStateChange?("混录已暂停")
        onProgress?(0, Int(accumulatedDuration.rounded()))
    }

    private func resumeMicrophoneRecording() throws {
        guard let recorder else {
            throw AudioSessionError.recorderUnavailable
        }

        try sessionCoordinator.configureForRecording()
        guard recorder.record() else {
            throw AudioSessionError.recorderUnavailable
        }

        recordingStartedAt = .now
        if !audioEngine.isRunning {
            try startPCMStreaming()
        }
        onCaptureStateChange?("麦克风已恢复")
        startMetering()
    }

    private func resumeMixedRecording() throws {
        guard recordingURL != nil else {
            throw AudioSessionError.recorderUnavailable
        }

        try sessionCoordinator.configureForRecording(allowsFilePlayback: true)
        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        recordingStartedAt = .now
        if shouldResumeSourceAfterRecordingPause {
            try playSourceAudioFromCurrentPosition(resetIfNeeded: true)
        }
        shouldResumeSourceAfterRecordingPause = false
        onCaptureStateChange?("混录已恢复")
    }

    private func stopMicrophoneRecording() throws -> LocalAudioArtifact {
        guard let recorder, let recordingURL else {
            throw AudioSessionError.recorderUnavailable
        }

        let finalDuration = max(Int(currentDuration().rounded()), Int(recorder.currentTime.rounded()))
        recorder.stop()
        stopMetering()
        stopPCMStreaming()
        self.recorder = nil
        self.recordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        onCaptureStateChange?("录音已停止")
        sessionCoordinator.deactivate()

        return LocalAudioArtifact(
            fileURL: recordingURL,
            durationSeconds: finalDuration,
            mimeType: "audio/m4a"
        )
    }

    private func stopMixedRecording() throws -> LocalAudioArtifact {
        guard let recordingURL else {
            throw AudioSessionError.recorderUnavailable
        }

        let finalDuration = Int(currentDuration().rounded())
        stopSourceProgressTimer()
        sourcePlaybackGeneration += 1
        playerNode?.stop()
        isSourceAudioPlaying = false
        removeRecordingMixerTapIfNeeded()
        cleanupMixedGraph()

        self.recordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        onCaptureStateChange?("录音已停止")
        sessionCoordinator.deactivate()

        return LocalAudioArtifact(
            fileURL: recordingURL,
            durationSeconds: finalDuration,
            mimeType: "audio/wav"
        )
    }

    private func currentDuration() -> TimeInterval {
        accumulatedDuration + (recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func reconcileMicrophoneRecordingAfterForeground() -> AudioRecorderForegroundRecoveryResult {
        guard let recorder, recordingURL != nil else {
            return .needsUserResume("录音在后台被系统打断，请返回应用后继续。")
        }

        var recovered = false

        do {
            try sessionCoordinator.configureForRecording()

            if !recorder.isRecording {
                guard recorder.record() else {
                    return .needsUserResume("录音在后台被系统打断，请返回应用后继续。")
                }
                recordingStartedAt = .now
                recovered = true
            }

            if !audioEngine.isRunning || !isInputTapInstalled {
                try startPCMStreaming()
                recovered = true
            }

            startMetering()
            recorder.updateMeters()
            onProgress?(normalizedPower(from: recorder), currentRecordingDurationSeconds())
            onCaptureStateChange?(recovered ? "麦克风已恢复" : "麦克风运行中")
            return recovered ? .recovered : .healthy
        } catch {
            return .needsUserResume("录音在后台被系统打断，请返回应用后继续。")
        }
    }

    private func reconcileMixedRecordingAfterForeground() -> AudioRecorderForegroundRecoveryResult {
        guard recordingURL != nil else {
            return .needsUserResume("录音在后台被系统打断，请返回应用后继续。")
        }

        var recovered = false

        do {
            try sessionCoordinator.configureForRecording(allowsFilePlayback: true)

            if !audioEngine.isRunning {
                try audioEngine.start()
                recovered = true
            }

            if recordingStartedAt == nil {
                recordingStartedAt = .now
                recovered = true
            }

            if isSourceAudioPlaying || shouldResumeSourceAfterRecordingPause {
                try playSourceAudioFromCurrentPosition(resetIfNeeded: true)
                shouldResumeSourceAfterRecordingPause = false
            } else {
                publishSourcePlaybackUpdate()
            }

            onProgress?(0, currentRecordingDurationSeconds())
            onCaptureStateChange?(recovered ? "混录已恢复" : "混录运行中")
            return recovered ? .recovered : .healthy
        } catch {
            return .needsUserResume("录音在后台被系统打断，请返回应用后继续。")
        }
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder else { return }
                recorder.updateMeters()
                self.onProgress?(self.normalizedPower(from: recorder), Int(self.currentDuration().rounded()))
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func startPCMStreaming() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        if isInputTapInstalled {
            inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let pcmData = PCMConverter.downsampledPCMData(from: buffer) else {
                return
            }

            let level = PCMConverter.normalizedRMSLevel(from: buffer)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onPCMData?(pcmData)
                self.onProgress?(level, Int(self.currentDuration().rounded()))
            }
        }

        isInputTapInstalled = true
        audioEngine.prepare()
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
    }

    private func stopPCMStreaming() {
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }

        // Microphone mode only uses an input tap. Pausing is enough here and avoids
        // tearing down the engine graph while Core Audio is still settling route changes.
        audioEngine.pause()
        onCaptureStateChange?("PCM 采集已停止")
    }

    private func installRecordingMixerTap(format: AVAudioFormat) {
        guard let recordingMixer else { return }

        removeRecordingMixerTapIfNeeded()
        recordingMixer.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.mixedRecordingFile?.write(from: buffer)
            guard let pcmData = PCMConverter.downsampledPCMData(from: buffer) else {
                return
            }

            let level = PCMConverter.normalizedRMSLevel(from: buffer)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onPCMData?(pcmData)
                self.onProgress?(level, Int(self.currentDuration().rounded()))
            }
        }
        isRecordingMixerTapInstalled = true
    }

    private func removeRecordingMixerTapIfNeeded() {
        guard isRecordingMixerTapInstalled, let recordingMixer else { return }
        recordingMixer.removeTap(onBus: 0)
        isRecordingMixerTapInstalled = false
    }

    private func pauseSourceAudioPlayback() {
        guard captureMode == .fileMix else { return }
        sourcePlaybackGeneration += 1
        sourceAudioFramePosition = currentSourceAudioFramePosition()
        playerNode?.stop()
        isSourceAudioPlaying = false
        stopSourceProgressTimer()
        publishSourcePlaybackUpdate()
    }

    private func playSourceAudioFromCurrentPosition(resetIfNeeded: Bool = false) throws {
        guard let sourceAudioFile, let playerNode else { return }

        if sourceAudioFramePosition >= sourceAudioTotalFrames {
            guard resetIfNeeded else {
                publishSourcePlaybackUpdate()
                return
            }
            sourceAudioFramePosition = 0
        }

        sourcePlaybackGeneration += 1
        let generation = sourcePlaybackGeneration
        let startFrame = sourceAudioFramePosition
        let remainingFrames = max(sourceAudioTotalFrames - startFrame, 0)
        guard remainingFrames > 0 else {
            publishSourcePlaybackUpdate()
            return
        }

        playerNode.stop()
        sourceAudioScheduledStartFrame = startFrame
        playerNode.scheduleSegment(
            sourceAudioFile,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.sourcePlaybackGeneration == generation else { return }
                self.sourceAudioFramePosition = self.sourceAudioTotalFrames
                self.isSourceAudioPlaying = false
                self.stopSourceProgressTimer()
                self.publishSourcePlaybackUpdate()
                self.onCaptureStateChange?("源音频播放完成")
            }
        }
        playerNode.play()
        isSourceAudioPlaying = true
        startSourceProgressTimer()
        publishSourcePlaybackUpdate()
    }

    private func currentSourceAudioFramePosition() -> AVAudioFramePosition {
        guard let playerNode, isSourceAudioPlaying else {
            return sourceAudioFramePosition
        }

        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return sourceAudioFramePosition
        }

        let offset = AVAudioFramePosition(max(playerTime.sampleTime, 0))
        return min(sourceAudioTotalFrames, sourceAudioScheduledStartFrame + offset)
    }

    private func startSourceProgressTimer() {
        stopSourceProgressTimer()
        sourceProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.publishSourcePlaybackUpdate()
            }
        }
    }

    private func stopSourceProgressTimer() {
        sourceProgressTimer?.invalidate()
        sourceProgressTimer = nil
    }

    private func publishSourcePlaybackUpdate() {
        let currentFrame = currentSourceAudioFramePosition()
        let currentTime = sourceAudioFile?.processingFormat.sampleRate ?? 0 > 0
            ? Double(currentFrame) / (sourceAudioFile?.processingFormat.sampleRate ?? 1)
            : 0

        onSourcePlaybackUpdate?(
            currentTime,
            sourceAudioDuration,
            isSourceAudioPlaying,
            sourceAudioDisplayName
        )
    }

    private func persistSourceAudio(_ asset: SourceAudioAsset, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = directory.appendingPathComponent(makeSourceAudioFilename(for: asset.fileURL))
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let requiresScopedAccess = asset.fileURL.startAccessingSecurityScopedResource()
        defer {
            if requiresScopedAccess {
                asset.fileURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.copyItem(at: asset.fileURL, to: destination)
        return destination
    }

    private func makeSourceAudioFilename(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? "source-audio" : "source-audio.\(ext)"
    }

    private func normalizedPower(from recorder: AVAudioRecorder) -> Double {
        let power = recorder.averagePower(forChannel: 0)
        let level = pow(10, power / 20)
        return max(0, min(Double(level), 1))
    }

    private func makeRecordingURL(meetingID: String, filename: String) throws -> URL {
        try makeMeetingDirectoryURL(meetingID: meetingID).appendingPathComponent(filename)
    }

    private func makeMeetingDirectoryURL(meetingID: String) throws -> URL {
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
        return directory
    }

    private func resetRuntimeState() {
        stopMetering()
        stopSourceProgressTimer()
        if recorder != nil {
            recorder?.stop()
            recorder = nil
        }
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        removeRecordingMixerTapIfNeeded()
        cleanupMixedGraph()
        recordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        captureMode = .microphone
    }

    private func cleanupMixedGraph() {
        audioEngine.pause()
        let hadCustomGraphNodes = playerNode != nil || recordingMixer != nil
        if let playerNode {
            sourcePlaybackGeneration += 1
            playerNode.stop()
            audioEngine.disconnectNodeInput(playerNode)
            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.detach(playerNode)
            self.playerNode = nil
        }
        if let recordingMixer {
            audioEngine.disconnectNodeInput(recordingMixer)
            audioEngine.disconnectNodeOutput(recordingMixer)
            audioEngine.detach(recordingMixer)
            self.recordingMixer = nil
        }
        if hadCustomGraphNodes {
            audioEngine.stop()
            audioEngine.reset()
        }
        mixedRecordingFile = nil
        sourceAudioFile = nil
        sourceAudioLocalURL = nil
        sourceAudioDisplayName = nil
        sourceAudioFramePosition = 0
        sourceAudioScheduledStartFrame = 0
        sourceAudioTotalFrames = 0
        sourceAudioDuration = 0
        isSourceAudioPlaying = false
        shouldResumeSourceAfterRecordingPause = false
        onSourcePlaybackUpdate?(0, 0, false, nil)
    }

    private func handleSessionLifecycleEvent(_ event: AudioSessionLifecycleEvent) {
        switch event {
        case .interruptionBegan:
            stopMetering()
            if captureMode == .fileMix {
                shouldResumeSourceAfterRecordingPause = isSourceAudioPlaying
            }
            onCaptureStateChange?("录音被系统打断")
        case let .interruptionEnded(shouldResume, _):
            onCaptureStateChange?(shouldResume ? "系统中断已结束" : "录音等待恢复")
        case .routeChanged:
            stopMetering()
            onCaptureStateChange?("音频路由已切换")
        case .mediaServicesWereLost:
            stopMetering()
            onCaptureStateChange?("音频服务已丢失")
        case .mediaServicesWereReset:
            onCaptureStateChange?("音频服务已重置")
        }

        onLifecycleEvent?(event)
    }
}
