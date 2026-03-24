import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol AudioFileTranscriptionServicing: AnyObject {
    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws
}

struct ImportedAudioFileDescriptor {
    let fileURL: URL
    let displayName: String
    let mimeType: String
    let durationSeconds: Int
}

enum AudioFileTranscriptionPhase: Equatable {
    case preparing
    case connecting
    case transcribing(elapsed: TimeInterval, total: TimeInterval)
    case finalizing
}

enum AudioFileTranscriptionError: LocalizedError {
    case invalidSessionResponse
    case invalidWebSocketURL
    case unreadableAudioFile
    case emptyAudioFile
    case timedOut
    case sessionCreationFailed(String)
    case connectionFailed(String)
    case audioDecodingFailed(String)
    case audioStreamingFailed(String)
    case normalizationFailed(String)
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .invalidSessionResponse:
            return "ASR 会话创建失败，返回数据不完整。"
        case .invalidWebSocketURL:
            return "ASR 会话地址无效。"
        case .unreadableAudioFile:
            return "当前音频文件在 iPhone 上无法读取，请先重新导出为 m4a、mp3 或 wav 后重试。"
        case .emptyAudioFile:
            return "音频文件没有可转写的内容。"
        case .timedOut:
            return "转写收尾超时，请稍后重试。"
        case let .sessionCreationFailed(detail):
            return "创建 ASR 会话失败：\(detail)"
        case let .connectionFailed(detail):
            return "ASR 连接失败：\(detail)"
        case let .audioDecodingFailed(detail):
            return "音频解码失败：\(detail)"
        case let .audioStreamingFailed(detail):
            return "音频发送失败：\(detail)"
        case let .normalizationFailed(detail):
            return "音频预处理失败：\(detail)"
        case let .serviceError(message):
            return message
        }
    }
}

private struct FileTranscriptionProxyASRMessage: Decodable {
    let type: String
    let text: String?
    let startTimeMs: Double?
    let endTimeMs: Double?
    let message: String?
}

private final class AudioFileTranscriptionDiagnostics {
    private var entries: [String]

    init(attempt: Int) {
        entries = ["attempt=\(attempt)"]
    }

    func record(_ entry: String) {
        entries.append(entry)
    }

    var summary: String {
        entries.suffix(8).joined(separator: " > ")
    }
}

private final class AudioFileTranscriptionAttemptProgress {
    var didEmitFinalResult = false
}

struct AudioFileTranscriptionTransportFailureContext: Equatable {
    let didBeginFinalization: Bool
    let didReceiveServiceError: Bool
    let didReceiveTranscriptText: Bool
    let didEmitFinalResult: Bool
    let closeCode: URLSessionWebSocketTask.CloseCode
}

enum AudioFileTranscriptionTransportFailureDisposition: Equatable {
    case finishGracefully
    case fail
}

private actor AudioFileTranscriptionTransportState {
    private var isReady = false
    private var isClosed = false
    private var terminalError: Error?
    private var didBeginFinalization = false
    private var didReceiveServiceError = false
    private var latestTranscriptText = ""
    private var didEmitFinalResult = false
    private var closeCode: URLSessionWebSocketTask.CloseCode = .invalid
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []

    func waitUntilReady() async throws {
        if let terminalError {
            throw terminalError
        }

        if isReady {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            readyContinuations.append(continuation)
        }
    }

    func markReady() {
        guard !isReady else { return }
        isReady = true
        let continuations = readyContinuations
        readyContinuations.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(returning: ()) }
    }

    func markFinalizationStarted() {
        didBeginFinalization = true
    }

    func markServiceErrorReceived() {
        didReceiveServiceError = true
    }

    func markPartialTextReceived(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        latestTranscriptText = normalized
    }

    func markFinalResultReceived() {
        didEmitFinalResult = true
    }

    func markFinalResultReceived(text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            latestTranscriptText = normalized
        }
        didEmitFinalResult = true
    }

    func markClosed(closeCode: URLSessionWebSocketTask.CloseCode? = nil) {
        if let closeCode {
            self.closeCode = closeCode
        }
        isClosed = true
    }

    func fail(_ error: Error) {
        guard terminalError == nil else { return }
        terminalError = error
        isClosed = true
        let continuations = readyContinuations
        readyContinuations.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(throwing: error) }
    }

    func ensureHealthy() throws {
        if let terminalError {
            throw terminalError
        }
    }

    func failureContext(closeCode overrideCloseCode: URLSessionWebSocketTask.CloseCode? = nil)
        -> AudioFileTranscriptionTransportFailureContext
    {
        if let overrideCloseCode {
            closeCode = overrideCloseCode
        }

        return AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: didBeginFinalization,
            didReceiveServiceError: didReceiveServiceError,
            didReceiveTranscriptText: !latestTranscriptText.isEmpty,
            didEmitFinalResult: didEmitFinalResult,
            closeCode: closeCode
        )
    }

    func fallbackFinalResult(totalDurationSeconds: Int) -> ASRFinalResult? {
        guard didBeginFinalization, !didReceiveServiceError, !didEmitFinalResult else {
            return nil
        }

        let normalized = latestTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let endTime = max(Double(totalDurationSeconds), 0) * 1000
        let startTime = max(0, endTime - 1_500)
        return ASRFinalResult(
            text: normalized,
            startTime: startTime,
            endTime: max(endTime, startTime)
        )
    }

    func waitUntilFinished(timeoutMS: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)

        while !isClosed {
            if let terminalError {
                throw terminalError
            }

            if Date() >= deadline {
                throw AudioFileTranscriptionError.timedOut
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        if let terminalError {
            throw terminalError
        }
    }
}

@MainActor
final class AudioFileTranscriptionService: AudioFileTranscriptionServicing {
    private let apiClient: APIClient
    private let injectedSession: URLSession?

    init(apiClient: APIClient, session: URLSession? = nil) {
        self.apiClient = apiClient
        self.injectedSession = session
    }

    static func importAudioFile(
        _ asset: SourceAudioAsset,
        meetingID: String
    ) async throws -> ImportedAudioFileDescriptor {
        let destination = try makeImportedAudioURL(meetingID: meetingID)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let requiresScopedAccess = asset.fileURL.startAccessingSecurityScopedResource()
        defer {
            if requiresScopedAccess {
                asset.fileURL.stopAccessingSecurityScopedResource()
            }
        }

        try await normalizeImportedAudioFile(from: asset.fileURL, to: destination)
        return try describeAudioFile(
            at: destination,
            fallbackDisplayName: asset.displayName,
            mimeTypeOverride: Self.normalizedImportedAudioMIMEType
        )
    }

    static func describeAudioFile(
        at fileURL: URL,
        fallbackDisplayName: String? = nil,
        mimeTypeOverride: String? = nil
    ) throws -> ImportedAudioFileDescriptor {
        let durationSeconds = try describeDurationSeconds(at: fileURL)
        let ext = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let mimeType = mimeTypeOverride
            ?? UTType(filenameExtension: ext)?.preferredMIMEType
            ?? "audio/mpeg"
        let derivedName = fileURL.deletingPathExtension().lastPathComponent
        let displayName = (fallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? fallbackDisplayName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : derivedName

        return ImportedAudioFileDescriptor(
            fileURL: fileURL,
            displayName: displayName,
            mimeType: mimeType,
            durationSeconds: durationSeconds
        )
    }

    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {
        let maximumAttempts = 2

        for attempt in 1 ... maximumAttempts {
            try Task.checkCancellation()

            let diagnostics = AudioFileTranscriptionDiagnostics(attempt: attempt)
            let progress = AudioFileTranscriptionAttemptProgress()

            do {
                try await transcribeAttempt(
                    fileURL: fileURL,
                    workspaceID: workspaceID,
                    diagnostics: diagnostics,
                    progress: progress,
                    onPhaseChange: onPhaseChange,
                    onPartialText: onPartialText,
                    onFinalResult: onFinalResult
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maximumAttempts,
                      !progress.didEmitFinalResult,
                      Self.isRetryableTransportFailure(error) else {
                    throw error
                }

                diagnostics.record("retrying-after-transient-transport-failure")
                onPartialText("")
                onPhaseChange(.connecting)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func transcribeAttempt(
        fileURL: URL,
        workspaceID: String?,
        diagnostics: AudioFileTranscriptionDiagnostics,
        progress: AudioFileTranscriptionAttemptProgress,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {
        onPhaseChange(.preparing)
        diagnostics.record("prepare")
        diagnostics.record("api-host=\(apiClient.baseURL?.host ?? "none")")
        let estimatedDurationSeconds = try Self.describeAudioFile(at: fileURL).durationSeconds

        let descriptor: RemoteASRSessionResponse
        do {
            diagnostics.record("create-session")
            descriptor = try await apiClient.createASRSession(
                sampleRate: Int(PCMConverter.targetSampleRate),
                channels: 1,
                workspaceID: workspaceID
            )
        } catch {
            throw AudioFileTranscriptionError.sessionCreationFailed(
                detailedError(error, diagnostics: diagnostics)
            )
        }

        guard let sessionDescriptor = descriptor.session else {
            throw AudioFileTranscriptionError.sessionCreationFailed(
                decorateDetail(
                    descriptor.error ?? AudioFileTranscriptionError.invalidSessionResponse.localizedDescription,
                    diagnostics: diagnostics
                )
            )
        }

        guard let webSocketURL = URL(string: sessionDescriptor.wsUrl) else {
            throw AudioFileTranscriptionError.invalidWebSocketURL
        }
        diagnostics.record("ws-host=\(webSocketURL.host ?? "unknown")")

        let packetDurationMs = max(sessionDescriptor.packetDurationMs ?? 100, 50)
        let sampleRate = sessionDescriptor.sampleRate ?? Int(PCMConverter.targetSampleRate)
        let channels = sessionDescriptor.channels ?? 1
        let packetByteSize = Self.makePacketByteSize(
            sampleRate: sampleRate,
            channels: channels,
            packetDurationMs: packetDurationMs
        )
        let bytesPerSecond = max(sampleRate, 8_000) * max(channels, 1) * 2
        let transportState = AudioFileTranscriptionTransportState()
        let socketSession = injectedSession ?? Self.makeWebSocketSession()
        let shouldInvalidateSession = injectedSession == nil
        let socketTask = socketSession.webSocketTask(with: webSocketURL)

        diagnostics.record("ws-resume")
        socketTask.resume()

        let receiveTask = Task { [weak self, socketTask] in
            guard let self else { return }
            await self.receiveLoop(
                task: socketTask,
                transportState: transportState,
                diagnostics: diagnostics,
                onPartialText: onPartialText,
                onFinalResult: { result in
                    progress.didEmitFinalResult = true
                    onFinalResult(result)
                }
            )
        }

        defer {
            receiveTask.cancel()
            socketTask.cancel(with: .goingAway, reason: nil)
            if shouldInvalidateSession {
                socketSession.invalidateAndCancel()
            }
        }

        onPhaseChange(.connecting)
        do {
            try await transportState.waitUntilReady()
            diagnostics.record("ws-ready")
            try await transportState.ensureHealthy()
            try await validateSocketConnection(
                socketTask: socketTask,
                transportState: transportState,
                diagnostics: diagnostics
            )
        } catch let error as AudioFileTranscriptionError {
            throw error
        } catch {
            throw AudioFileTranscriptionError.connectionFailed(
                detailedError(error, diagnostics: diagnostics)
            )
        }

        let sentAnyAudio: Bool
        do {
            diagnostics.record("stream-start")
            diagnostics.record("stream-backend=asset-reader")
            sentAnyAudio = try await streamAudioFile(
                from: fileURL,
                backend: .assetReader,
                packetByteSize: packetByteSize,
                packetDurationMs: packetDurationMs,
                bytesPerSecond: bytesPerSecond,
                estimatedDurationSeconds: estimatedDurationSeconds,
                transportState: transportState,
                socketTask: socketTask,
                diagnostics: diagnostics,
                onPhaseChange: onPhaseChange
            )
        } catch {
            throw error
        }

        guard sentAnyAudio else {
            throw AudioFileTranscriptionError.emptyAudioFile
        }

        onPhaseChange(.finalizing)
        await transportState.markFinalizationStarted()
        do {
            diagnostics.record("send-stop")
            try await socketTask.send(.string("{\"type\":\"stop\"}"))
        } catch {
            let closeCode = socketTask.closeCode
            let failureContext = await transportState.failureContext(closeCode: closeCode)
            if Self.classifyTransportFailure(error, context: failureContext) == .finishGracefully {
                diagnostics.record("stop-after-close=\(Self.describeCloseCode(closeCode))")
                await transportState.markClosed(closeCode: closeCode)
            } else {
                throw AudioFileTranscriptionError.audioStreamingFailed(
                    detailedError(error, diagnostics: diagnostics)
                )
            }
        }

        do {
            try await transportState.waitUntilFinished(timeoutMS: 5_000)
            if !progress.didEmitFinalResult,
               let fallbackResult = await transportState.fallbackFinalResult(
                   totalDurationSeconds: estimatedDurationSeconds
               ) {
                diagnostics.record("synthesized-final-from-partial")
                progress.didEmitFinalResult = true
                onFinalResult(fallbackResult)
            }
            diagnostics.record("finished")
        } catch {
            throw AudioFileTranscriptionError.audioStreamingFailed(
                detailedError(error, diagnostics: diagnostics)
            )
        }
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        transportState: AudioFileTranscriptionTransportState,
        diagnostics: AudioFileTranscriptionDiagnostics,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case let .string(text):
                    await handleMessage(
                        text,
                        transportState: transportState,
                        diagnostics: diagnostics,
                        onPartialText: onPartialText,
                        onFinalResult: onFinalResult
                    )
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(
                            text,
                            transportState: transportState,
                            diagnostics: diagnostics,
                            onPartialText: onPartialText,
                            onFinalResult: onFinalResult
                        )
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                let closeCode = task.closeCode
                let failureContext = await transportState.failureContext(closeCode: closeCode)
                if Self.classifyTransportFailure(error, context: failureContext) == .finishGracefully {
                    diagnostics.record("receive-finished=\(Self.describeCloseCode(closeCode))")
                    await transportState.markClosed(closeCode: closeCode)
                } else {
                    diagnostics.record("receive-error=\(Self.describeCloseCode(closeCode))")
                    await transportState.fail(error)
                }
                return
            }
        }
    }

    private func handleMessage(
        _ text: String,
        transportState: AudioFileTranscriptionTransportState,
        diagnostics: AudioFileTranscriptionDiagnostics,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(FileTranscriptionProxyASRMessage.self, from: data) else {
            return
        }

        switch message.type {
        case "ready":
            diagnostics.record("proxy-ready")
            await transportState.markReady()

        case "partial":
            let partialText = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await transportState.markPartialTextReceived(partialText)
            onPartialText(partialText)

        case "final":
            let finalText = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !finalText.isEmpty else { return }
            let startTime = message.startTimeMs ?? 0
            let endTime = max(message.endTimeMs ?? startTime, startTime)
            await transportState.markFinalResultReceived(text: finalText)
            onFinalResult(
                ASRFinalResult(
                    text: finalText,
                    startTime: startTime,
                    endTime: endTime
                )
            )

        case "error":
            let detail = message.message ?? "文件转写服务异常。"
            diagnostics.record("proxy-error")
            await transportState.markServiceErrorReceived()
            await transportState.fail(
                AudioFileTranscriptionError.serviceError(
                    decorateDetail(detail, diagnostics: diagnostics)
                )
            )

        case "closed":
            diagnostics.record("proxy-closed")
            await transportState.markClosed(closeCode: .normalClosure)

        default:
            break
        }
    }

    private static var normalizedImportedAudioFilename: String {
        let ext = UTType.mpeg4Audio.preferredFilenameExtension ?? "m4a"
        return "imported-audio.\(ext)"
    }

    private static var normalizedImportedAudioMIMEType: String {
        UTType.mpeg4Audio.preferredMIMEType ?? "audio/m4a"
    }

    private static func makeImportedAudioURL(meetingID: String) throws -> URL {
        let directory = try makeMeetingDirectoryURL(meetingID: meetingID)
        return directory.appendingPathComponent(normalizedImportedAudioFilename)
    }

    private static func makeMeetingDirectoryURL(meetingID: String) throws -> URL {
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

    private static func makePacketByteSize(sampleRate: Int, channels: Int, packetDurationMs: Int) -> Int {
        let normalizedRate = max(sampleRate, 8_000)
        let normalizedChannels = max(channels, 1)
        let normalizedDuration = max(packetDurationMs, 50)
        let bytesPerSecond = normalizedRate * normalizedChannels * 2
        let computedSize = Int((Double(bytesPerSecond) * Double(normalizedDuration)) / 1000)
        return max(computedSize, 3_200)
    }

    private func streamAudioFile(
        from fileURL: URL,
        backend: AudioPCMFileStreamer.Backend = .avAudioFile,
        packetByteSize: Int,
        packetDurationMs: Int,
        bytesPerSecond: Int,
        estimatedDurationSeconds: Int,
        transportState: AudioFileTranscriptionTransportState,
        socketTask: URLSessionWebSocketTask,
        diagnostics: AudioFileTranscriptionDiagnostics,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void
    ) async throws -> Bool {
        var pendingPCMBuffer = Data()
        var sentAnyAudio = false
        var sentDurationSeconds: TimeInterval = 0
        var sentChunkCount = 0

        do {
            for try await chunk in AudioPCMFileStreamer.pcmChunkStream(from: fileURL, backend: backend) {
                try Task.checkCancellation()
                try await transportState.ensureHealthy()

                pendingPCMBuffer.append(chunk)
                while pendingPCMBuffer.count >= packetByteSize {
                    let payload = Data(pendingPCMBuffer.prefix(packetByteSize))
                    pendingPCMBuffer.removeFirst(packetByteSize)
                    try await sendPCMChunk(
                        payload,
                        packetDurationMs: packetDurationMs,
                        isFirstChunk: sentChunkCount == 0,
                        transportState: transportState,
                        socketTask: socketTask,
                        diagnostics: diagnostics
                    )
                    sentAnyAudio = true
                    sentChunkCount += 1
                    sentDurationSeconds += Double(payload.count) / Double(bytesPerSecond)
                    onPhaseChange(
                        .transcribing(
                            elapsed: min(sentDurationSeconds, max(Double(estimatedDurationSeconds), sentDurationSeconds)),
                            total: max(Double(estimatedDurationSeconds), sentDurationSeconds)
                        )
                    )
                }
            }
        } catch let error as AudioFileTranscriptionError {
            throw error
        } catch {
            throw AudioFileTranscriptionError.audioDecodingFailed(
                detailedError(error, diagnostics: diagnostics)
            )
        }

        if !pendingPCMBuffer.isEmpty {
            try await sendPCMChunk(
                pendingPCMBuffer,
                packetDurationMs: max(
                    20,
                    Int((Double(pendingPCMBuffer.count) / Double(bytesPerSecond) * 1000).rounded())
                ),
                isFirstChunk: sentChunkCount == 0,
                transportState: transportState,
                socketTask: socketTask,
                diagnostics: diagnostics
            )
            sentAnyAudio = true
            sentChunkCount += 1
            sentDurationSeconds += Double(pendingPCMBuffer.count) / Double(bytesPerSecond)
            onPhaseChange(
                .transcribing(
                    elapsed: min(sentDurationSeconds, max(Double(estimatedDurationSeconds), sentDurationSeconds)),
                    total: max(Double(estimatedDurationSeconds), sentDurationSeconds)
                )
            )
        }

        diagnostics.record("streamed-chunks=\(sentChunkCount)")
        return sentAnyAudio
    }

    private func sendPCMChunk(
        _ payload: Data,
        packetDurationMs: Int,
        isFirstChunk: Bool,
        transportState: AudioFileTranscriptionTransportState,
        socketTask: URLSessionWebSocketTask,
        diagnostics: AudioFileTranscriptionDiagnostics
    ) async throws {
        do {
            try await transportState.ensureHealthy()
            if isFirstChunk {
                diagnostics.record("send-first-audio")
            }
            try await socketTask.send(.data(payload))
            try await Task.sleep(for: .milliseconds(packetDurationMs))
            try await transportState.ensureHealthy()
        } catch let error as AudioFileTranscriptionError {
            throw error
        } catch {
            throw AudioFileTranscriptionError.audioStreamingFailed(
                detailedError(error, diagnostics: diagnostics)
            )
        }
    }

    private static func normalizeImportedAudioFile(
        from sourceURL: URL,
        to outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioFileTranscriptionError.normalizationFailed("当前音频文件在 iPhone 上无法自动转换，请先重新导出为 m4a、mp3 或 wav 后重试。")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        switch exporter.status {
        case .completed:
            return
        case .failed:
            throw AudioFileTranscriptionError.normalizationFailed(
                Self.userVisibleAudioProcessingMessage(
                    for: exporter.error,
                    fallback: "当前音频文件在 iPhone 上无法自动转换，请先重新导出为 m4a、mp3 或 wav 后重试。"
                )
            )
        case .cancelled:
            throw CancellationError()
        default:
            throw AudioFileTranscriptionError.normalizationFailed("音频文件转换未完成，请稍后重试。")
        }
    }

    private static func describeDurationSeconds(at fileURL: URL) throws -> Int {
        let asset = AVURLAsset(url: fileURL)
        let assetDurationSeconds = CMTimeGetSeconds(asset.duration)
        if assetDurationSeconds.isFinite, assetDurationSeconds > 0 {
            return max(0, Int(assetDurationSeconds.rounded()))
        }

        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let sampleRate = audioFile.processingFormat.sampleRate
            guard sampleRate > 0 else {
                return 0
            }
            return max(0, Int((Double(audioFile.length) / sampleRate).rounded()))
        } catch {
            throw AudioFileTranscriptionError.unreadableAudioFile
        }
    }

    private func validateSocketConnection(
        socketTask: URLSessionWebSocketTask,
        transportState: AudioFileTranscriptionTransportState,
        diagnostics: AudioFileTranscriptionDiagnostics
    ) async throws {
        try await transportState.ensureHealthy()
        diagnostics.record("send-ping")

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        socketTask.sendPing { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: ())
                            }
                        }
                    }
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(2))
                    throw AudioFileTranscriptionError.connectionFailed("WebSocket ping 超时。")
                }

                _ = try await group.next()
                group.cancelAll()
            }

            diagnostics.record("receive-pong")
            try await Task.sleep(for: .milliseconds(120))
            try await transportState.ensureHealthy()
        } catch {
            throw AudioFileTranscriptionError.connectionFailed(
                detailedError(error, diagnostics: diagnostics)
            )
        }
    }

    private static func makeWebSocketSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldUsePipelining = true
        return URLSession(configuration: configuration)
    }

    private func detailedError(
        _ error: Error,
        diagnostics: AudioFileTranscriptionDiagnostics
    ) -> String {
        decorateDetail(Self.describe(error), diagnostics: diagnostics)
    }

    private func decorateDetail(
        _ detail: String,
        diagnostics: AudioFileTranscriptionDiagnostics
    ) -> String {
        let compactDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = diagnostics.summary
        guard !summary.isEmpty else { return compactDetail }
        return "\(compactDetail) | 轨迹: \(summary)"
    }

    nonisolated static func userVisibleAudioProcessingMessage(
        for error: Error?,
        fallback: String
    ) -> String {
        guard let error else {
            return fallback
        }

        if let mapped = mappedAudioProcessingMessage(for: error) {
            return mapped
        }

        let message = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private static func describe(_ error: Error) -> String {
        if let mapped = mappedAudioProcessingMessage(for: error) {
            return mapped
        }

        let nsError = error as NSError
        var parts = ["\(nsError.domain) code=\(nsError.code)", nsError.localizedDescription]

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain) code=\(underlying.code) \(underlying.localizedDescription)")
        }

        return parts.joined(separator: " ")
    }

    private nonisolated static func mappedAudioProcessingMessage(for error: Error) -> String? {
        let nsError = error as NSError
        let normalizedDescription = nsError.localizedDescription.lowercased()

        if nsError.domain.contains("GenericObjCError")
            || normalizedDescription.contains("genericobjcerror")
            || normalizedDescription.contains("operation couldn")
        {
            return "当前音频文件在 iPhone 上无法稳定解析，请先重新导出为 m4a、mp3 或 wav 后重试。"
        }

        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case AVError.fileFormatNotRecognized.rawValue:
                return "当前音频文件格式无法识别，请重新导出为 m4a、mp3 或 wav 后重试。"
            case AVError.decoderNotFound.rawValue:
                return "当前音频文件缺少可用解码器，请重新导出为 m4a、mp3 或 wav 后重试。"
            case AVError.invalidSourceMedia.rawValue:
                return "当前音频文件内容无效，请更换文件后重试。"
            default:
                break
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return mappedAudioProcessingMessage(for: underlying)
        }

        return nil
    }

    private nonisolated static func isRetryableTransportFailure(_ error: Error) -> Bool {
        let normalizedMessage = error.localizedDescription.lowercased()
        if normalizedMessage.contains("socket is not connected") ||
            normalizedMessage.contains("network connection was lost") ||
            normalizedMessage.contains("not connected to the internet") ||
            normalizedMessage.contains("timed out") ||
            normalizedMessage.contains("connection aborted") {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
            return true
        }

        if nsError.domain == NSURLErrorDomain {
            let retryableCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
            ]
            return retryableCodes.contains(nsError.code)
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isRetryableTransportFailure(underlying)
        }

        return false
    }

    nonisolated static func classifyTransportFailure(
        _ error: Error,
        context: AudioFileTranscriptionTransportFailureContext
    ) -> AudioFileTranscriptionTransportFailureDisposition {
        guard context.didBeginFinalization else {
            return .fail
        }

        guard !context.didReceiveServiceError else {
            return .fail
        }

        guard !(error is AudioFileTranscriptionError) else {
            return .fail
        }

        switch context.closeCode {
        case .normalClosure, .goingAway:
            return .finishGracefully
        case .invalid, .noStatusReceived, .abnormalClosure:
            if (context.didEmitFinalResult || context.didReceiveTranscriptText),
               isRetryableTransportFailure(error) {
                return .finishGracefully
            }
            return .fail
        default:
            return .fail
        }
    }

    private nonisolated static func describeCloseCode(_ closeCode: URLSessionWebSocketTask.CloseCode) -> String {
        switch closeCode {
        case .invalid:
            return "invalid"
        case .normalClosure:
            return "normalClosure"
        case .goingAway:
            return "goingAway"
        case .protocolError:
            return "protocolError"
        case .unsupportedData:
            return "unsupportedData"
        case .noStatusReceived:
            return "noStatusReceived"
        case .abnormalClosure:
            return "abnormalClosure"
        case .invalidFramePayloadData:
            return "invalidFramePayloadData"
        case .policyViolation:
            return "policyViolation"
        case .messageTooBig:
            return "messageTooBig"
        case .mandatoryExtensionMissing:
            return "mandatoryExtensionMissing"
        case .internalServerError:
            return "internalServerError"
        case .tlsHandshakeFailure:
            return "tlsHandshakeFailure"
        @unknown default:
            return "unknown(\(closeCode.rawValue))"
        }
    }
}
