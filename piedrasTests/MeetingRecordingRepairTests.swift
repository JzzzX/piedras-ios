import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import piedras

@MainActor
private final class MeetingRecordingRepairMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class StubAudioFileTranscriptionService: AudioFileTranscriptionServicing {
    enum Behavior {
        case succeed([ASRFinalResult])
        case fail(String)
    }

    var behavior: Behavior
    private(set) var transcribeCalls = 0
    var shouldSuspendTranscription = false
    private var transcriptionContinuation: CheckedContinuation<Void, Never>?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {
        transcribeCalls += 1
        onPhaseChange(.preparing)
        onPhaseChange(.connecting)

        if shouldSuspendTranscription {
            await withCheckedContinuation { continuation in
                transcriptionContinuation = continuation
            }
        }

        switch behavior {
        case let .succeed(results):
            onPartialText("partial")
            for result in results {
                onFinalResult(result)
            }
            onPartialText("")
        case let .fail(message):
            throw APIClientError.requestFailed(message)
        }
    }

    func resumeTranscription() {
        transcriptionContinuation?.resume()
        transcriptionContinuation = nil
    }
}

@MainActor
private final class StubASRService: ASRServicing {
    var onPartialText: ((String) -> Void)?
    var onFinalResult: ((ASRFinalResult) -> Void)?
    var onRecognitionSnapshot: ((ASRRecognitionSnapshot) -> Void)?
    var onStateChange: ((ASRConnectionState) -> Void)?
    var onError: ((String) -> Void)?
    var onTransportEvent: ((String) -> Void)?
    var onPCMChunkSent: ((Int) -> Void)?

    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func startStreaming(workspaceID: String?, meetingID: String?) async throws {
        startCalls += 1
    }

    func enqueuePCM(_ data: Data) {}

    func stopStreaming() async {
        stopCalls += 1
    }
}

@MainActor
private final class StubAudioRecorderService: AudioRecorderServicing {
    var onProgress: ((Double, Int) -> Void)?
    var onPCMData: ((Data) -> Void)?
    var onCaptureStateChange: ((String) -> Void)?
    var onSourcePlaybackUpdate: ((TimeInterval, TimeInterval, Bool, String?) -> Void)?
    var onLifecycleEvent: ((AudioSessionLifecycleEvent) -> Void)?

    var reconcileResult: AudioRecorderForegroundRecoveryResult = .healthy
    var currentDurationSecondsValue = 0
    var snapshotArtifact: RecordingSnapshotArtifact?
    var startArtifact = RecordingStartArtifact(
        fileURL: URL(fileURLWithPath: "/tmp/recording-start.m4a"),
        mimeType: "audio/m4a",
        inputMode: .microphone,
        sourceAudioLocalPath: nil,
        sourceAudioDisplayName: nil,
        sourceAudioDurationSeconds: 0
    )
    var stopArtifact = LocalAudioArtifact(
        fileURL: URL(fileURLWithPath: "/tmp/recording-stop.m4a"),
        durationSeconds: 0,
        mimeType: "audio/m4a"
    )

    func startRecording(
        meetingID: String,
        sourceAudio: SourceAudioAsset?
    ) async throws -> RecordingStartArtifact {
        startArtifact
    }

    func pauseRecording() throws {}
    func resumeRecording() throws {}

    func stopRecording() throws -> LocalAudioArtifact {
        stopArtifact
    }

    func toggleSourceAudioPlayback() throws {}

    func reconcileForegroundRecording() -> AudioRecorderForegroundRecoveryResult {
        reconcileResult
    }

    func currentRecordingDurationSeconds() -> Int {
        currentDurationSecondsValue
    }

    func makeRecordingSnapshot() throws -> RecordingSnapshotArtifact? {
        snapshotArtifact
    }

    func emitPCM(_ data: Data) {
        onPCMData?(data)
    }
}

@MainActor
private final class StubMeetingSyncService: MeetingSyncServicing {
    private let repository: MeetingRepository

    private(set) var syncedMeetingIDs: [String] = []
    private(set) var transcriptSnapshotsAtSync: [String] = []
    var shouldSuspendSync = false
    private var syncContinuation: CheckedContinuation<Void, Never>?

    init(repository: MeetingRepository) {
        self.repository = repository
    }

    func syncPendingMeetings() async -> MeetingSyncBatchResult {
        .init(syncedCount: 0, failedCount: 0)
    }

    func syncMeeting(id: String) async throws {
        syncedMeetingIDs.append(id)
        if shouldSuspendSync {
            await withCheckedContinuation { continuation in
                syncContinuation = continuation
            }
        }
        if let meeting = try repository.meeting(withID: id) {
            if meeting.speakerDiarizationState == .processing {
                meeting.speakerDiarizationState = .ready
                meeting.transcriptPipelineState = .ready
                meeting.speakerDiarizationErrorMessage = nil
            }
            meeting.syncState = .synced
            meeting.lastSyncedAt = .now
            try repository.save()
        }
        let transcript = try repository.meeting(withID: id)?.transcriptText ?? ""
        transcriptSnapshotsAtSync.append(transcript)
    }

    func refreshRemoteMeetings() async throws -> Int {
        0
    }

    func resumeSync() {
        syncContinuation?.resume()
        syncContinuation = nil
    }
}

@MainActor
private final class StubRecordingLiveActivityCoordinator: RecordingLiveActivityCoordinating {
    enum Event: Equatable {
        case start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int)
        case update(phase: RecordingLiveActivityPhase, durationSeconds: Int)
        case end
    }

    private(set) var events: [Event] = []

    func start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int) {
        events.append(.start(meetingID: meetingID, phase: phase, durationSeconds: durationSeconds))
    }

    func update(phase: RecordingLiveActivityPhase, durationSeconds: Int) {
        events.append(.update(phase: phase, durationSeconds: durationSeconds))
    }

    func end() {
        events.append(.end)
    }
}

@Suite(.serialized)
struct MeetingRecordingRepairTests {
    @MainActor
    @Test
    func stopRecordingWithoutTranscriptStillGeneratesAiNotesFromUserNotes() async throws {
        MeetingRecordingRepairMockURLProtocol.reset()
        defer { MeetingRecordingRepairMockURLProtocol.reset() }

        var enhanceCalls = 0
        MeetingRecordingRepairMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            switch url.path {
            case "/api/enhance":
                enhanceCalls += 1
                let body = try requestBodyData(from: request)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["transcript"] as? String == "")
                #expect((json["userNotes"] as? String)?.contains("客户反馈") == true)

                let payload: [String: Any] = [
                    "content": "## 会议摘要\n- 根据用户笔记整理出的结论",
                    "provider": "test"
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            default:
                throw URLError(.unsupportedURL)
            }
        }

        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.userNotesPlainText = "先整理这周的客户反馈，再补一版路线图。"
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording

        let audioURL = try makeTemporaryAudioFile(named: "stop-without-transcript-generates-notes.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 11,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.transcriptPipelineState == .ready)
        #expect(enhanceCalls == 1)
        #expect(refreshedMeeting.enhancedNotes.contains("根据用户笔记整理出的结论"))
    }

    @MainActor
    @Test
    func emptyRepairTranscriptFallsBackToNotesOnlyFinalizationWhenNoTranscriptExists() async throws {
        MeetingRecordingRepairMockURLProtocol.reset()
        defer { MeetingRecordingRepairMockURLProtocol.reset() }

        var enhanceCalls = 0
        MeetingRecordingRepairMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            switch url.path {
            case "/api/enhance":
                enhanceCalls += 1
                let body = try requestBodyData(from: request)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["transcript"] as? String == "")
                #expect((json["userNotes"] as? String)?.contains("客户反馈") == true)

                let payload: [String: Any] = [
                    "content": "## 会议摘要\n- 仅基于用户笔记整理",
                    "provider": "test"
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            default:
                throw URLError(.unsupportedURL)
            }
        }

        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.userNotesPlainText = "客户反馈需要先收敛，再补路线图。"
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.markTranscriptCoverageGap()

        let audioURL = try makeTemporaryAudioFile(named: "empty-repair-transcript-notes-only.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 12,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.transcriptPipelineState == .ready)
        #expect(refreshedMeeting.speakerDiarizationState == .idle)
        #expect(refreshedMeeting.speakerDiarizationErrorMessage == nil)
        #expect(refreshedMeeting.orderedSegments.isEmpty)
        #expect(refreshedMeeting.enhancedNotes.contains("仅基于用户笔记整理"))
        #expect(enhanceCalls == 1)
        #expect(fixture.transcriber.transcribeCalls == 1)
        #expect(fixture.syncService.syncedMeetingIDs == [meeting.id])
        #expect(fixture.syncService.transcriptSnapshotsAtSync == [""])
        #expect(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id) == nil)
    }

    @MainActor
    @Test
    func createMeetingForHomeRecordingPrimesRecordingStateBeforeNavigation() throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))

        let meeting = try #require(fixture.meetingStore.createMeeting(startingRecording: true))

        #expect(fixture.recordingSessionStore.meetingID == meeting.id)
        #expect(fixture.recordingSessionStore.phase == .starting)
        #expect(fixture.recordingSessionStore.asrState == .connecting)
        #expect(fixture.recordingSessionStore.inputMode == .microphone)
    }

    @MainActor
    @Test
    func backgroundingActiveRecordingKeepsLiveAsrRunningWithoutStartingFallback() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 2
        fixture.recorder.currentDurationSecondsValue = 2

        fixture.meetingStore.handleScenePhaseChange(.background)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))

        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)
        #expect(fixture.recordingSessionStore.backgroundTranscriptionStatus == .inactive)
        #expect(fixture.recordingSessionStore.backgroundChunkStartTimeMS == nil)
        #expect(fixture.recordingSessionStore.backgroundChunkBufferedDurationMS == 0)
        #expect(fixture.recordingSessionStore.infoBanner == nil)
        #expect(fixture.asrService.stopCalls == 0)
        #expect(fixture.transcriber.transcribeCalls == 0)
    }

    @MainActor
    @Test
    func backgroundRealtimeFailureUsesShadowBufferedAudioForFallback() async throws {
        let transcribedResults = [
            ASRFinalResult(text: "后台分片", startTime: 500, endTime: 2_200)
        ]
        let fixture = try makeFixture(transcriptionBehavior: .succeed(transcribedResults))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 2
        fixture.recorder.currentDurationSecondsValue = 2

        fixture.meetingStore.handleScenePhaseChange(.background)
        #expect(fixture.asrService.stopCalls == 0)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))
        #expect(fixture.transcriber.transcribeCalls == 0)

        fixture.asrService.onError?("bg fail")
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 7_500))
        try await waitUntil { fixture.transcriber.transcribeCalls == 1 }

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["后台分片"])
        #expect(refreshedMeeting.orderedSegments.map(\.startTime) == [2_500])
        #expect(fixture.recordingSessionStore.backgroundTranscriptionStatus == .chunking)
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)
        #expect(fixture.recordingSessionStore.infoBanner == nil)
        #expect(fixture.recordingSessionStore.errorBanner == nil)
        #expect(fixture.asrService.startCalls == 0)
    }

    @MainActor
    @Test
    func returningForegroundAfterHealthyBackgroundDoesNotRestartLiveAsrOrFlushFallback() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 3
        fixture.recorder.currentDurationSecondsValue = 3

        fixture.meetingStore.handleScenePhaseChange(.background)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))
        fixture.meetingStore.handleScenePhaseChange(.active)
        #expect(fixture.recordingSessionStore.backgroundTranscriptionStatus == .inactive)
        #expect(fixture.recordingSessionStore.infoBanner == nil)
        #expect(fixture.recordingSessionStore.errorBanner == nil)
        #expect(fixture.asrService.stopCalls == 0)
        #expect(fixture.asrService.startCalls == 0)
        #expect(fixture.transcriber.transcribeCalls == 0)
    }

    @MainActor
    @Test
    func stopRecordingAfterHealthyBackgroundDoesNotRunRepairTranscription() async throws {
        let fixture = try makeFixture(
            transcriptionBehavior: .succeed([
                ASRFinalResult(text: "不该触发", startTime: 0, endTime: 1_000)
            ])
        )
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 3
        fixture.recorder.currentDurationSecondsValue = 3

        fixture.meetingStore.handleScenePhaseChange(.background)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))

        let audioURL = try makeTemporaryAudioFile(named: "healthy-background-stop.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 8,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.transcriptPipelineState == .ready)
        #expect(fixture.transcriber.transcribeCalls == 0)
        #expect(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id) == nil)
    }

    @MainActor
    @Test
    func stopRecordingWithoutRepairDoesNotExposeTranscriptionStateWhileSyncIsInFlight() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.syncService.shouldSuspendSync = true

        let audioURL = try makeTemporaryAudioFile(named: "stop-without-repair-no-transcribing.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let stopTask = Task { @MainActor in
            await fixture.meetingStore.finishStoppedRecording(
                meetingID: meeting.id,
                artifact: LocalAudioArtifact(
                    fileURL: audioURL,
                    durationSeconds: 8,
                    mimeType: "audio/m4a"
                )
            )
        }

        try await waitUntil { fixture.syncService.syncedMeetingIDs == [meeting.id] }

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.speakerDiarizationState == .idle)
        #expect(refreshedMeeting.transcriptPipelineState == .ready)
        #expect(refreshedMeeting.postStopProcessingStage == .finalizing)
        #expect(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id) == nil)

        fixture.syncService.resumeSync()
        await stopTask.value

        let finalizedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(finalizedMeeting.postStopProcessingStage == .idle)
    }

    @MainActor
    @Test
    func healthyBackgroundShadowBufferRolloverDoesNotMarkCoverageGap() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 65
        fixture.recorder.currentDurationSecondsValue = 65

        fixture.meetingStore.handleScenePhaseChange(.background)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 70_000))

        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)
        #expect(fixture.recordingSessionStore.hasBackgroundTranscriptGap == false)
    }

    @MainActor
    @Test
    func backgroundChunkingDoesNotFailWhenChunkContainsOnlySilence() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 2
        fixture.recorder.currentDurationSecondsValue = 2

        fixture.meetingStore.handleScenePhaseChange(.background)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))
        fixture.asrService.onError?("bg fail")
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 7_500))

        try await waitUntil { fixture.transcriber.transcribeCalls >= 1 }

        #expect(fixture.transcriber.transcribeCalls == 1)
        #expect(fixture.recordingSessionStore.backgroundChunkFailureNeedsRepair == false)
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)
        #expect(fixture.recordingSessionStore.backgroundTranscriptionStatus == .chunking)
        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.orderedSegments.isEmpty)
    }

    @MainActor
    @Test
    func returningForegroundAfterBackgroundFallbackFlushesTailAndRestartsLiveAsr() async throws {
        let transcribedResults = [
            ASRFinalResult(text: "后台尾段", startTime: 0, endTime: 900)
        ]
        let fixture = try makeFixture(transcriptionBehavior: .succeed(transcribedResults))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 3
        fixture.recorder.currentDurationSecondsValue = 3

        fixture.meetingStore.handleScenePhaseChange(.background)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))
        fixture.asrService.onError?("bg fail")
        fixture.meetingStore.handleScenePhaseChange(.active)
        try await waitUntil {
            fixture.transcriber.transcribeCalls == 1 && fixture.asrService.startCalls == 1
        }

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["后台尾段"])
        #expect(refreshedMeeting.orderedSegments.map(\.startTime) == [3_000])
        #expect(fixture.recordingSessionStore.backgroundTranscriptionStatus == .inactive)
        #expect(fixture.recordingSessionStore.infoBanner == nil)
        #expect(fixture.recordingSessionStore.errorBanner == nil)
    }

    @MainActor
    @Test
    func backgroundChunkFailureRetriesOnceThenFallsBackToStopRepair() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .fail("chunk failed"))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 2
        fixture.recorder.currentDurationSecondsValue = 2

        fixture.meetingStore.handleScenePhaseChange(.background)
        #expect(fixture.asrService.stopCalls == 0)
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 5_000))
        fixture.asrService.onError?("chunk failed")
        fixture.recorder.emitPCM(makePCMChunk(durationMS: 7_500))
        try await waitUntil { fixture.transcriber.transcribeCalls == 2 }

        #expect(fixture.recordingSessionStore.backgroundChunkFailureNeedsRepair)
        #expect(fixture.recordingSessionStore.backgroundTranscriptionStatus == .failedNeedsRepair)
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop)
        #expect(fixture.recordingSessionStore.infoBanner == nil)
        #expect(fixture.recordingSessionStore.errorBanner == nil)
        #expect(fixture.asrService.stopCalls == 0)
        #expect(fixture.asrService.startCalls == 0)
    }

    @MainActor
    @Test
    func recordingLifecycleDrivesLiveActivityState() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        let recordingURL = try makeTemporaryAudioFile(named: "recording-live-activity-start.m4a")
        let stopURL = try makeTemporaryAudioFile(named: "recording-live-activity-stop.m4a")
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            try? FileManager.default.removeItem(at: stopURL)
        }

        fixture.recorder.startArtifact = RecordingStartArtifact(
            fileURL: recordingURL,
            mimeType: "audio/m4a",
            inputMode: .microphone,
            sourceAudioLocalPath: nil,
            sourceAudioDisplayName: nil,
            sourceAudioDurationSeconds: 0
        )
        fixture.recorder.stopArtifact = LocalAudioArtifact(
            fileURL: stopURL,
            durationSeconds: 3,
            mimeType: "audio/m4a"
        )

        await fixture.meetingStore.startRecording(meetingID: meeting.id)
        await fixture.meetingStore.pauseRecording()
        await fixture.meetingStore.resumeRecording()
        await fixture.meetingStore.stopRecording()
        try await waitUntil {
            fixture.liveActivity.events.contains(.end)
        }

        #expect(
            fixture.liveActivity.events == [
                .start(meetingID: meeting.id, phase: .recording, durationSeconds: 0),
                .update(phase: .paused, durationSeconds: 0),
                .update(phase: .recording, durationSeconds: 0),
                .end,
            ]
        )
    }

    @MainActor
    @Test
    func stopRecordingWithCoverageGapRepairsTranscriptBeforeSync() async throws {
        let repairedResult = ASRFinalResult(
            text: "完整补转写",
            startTime: 0,
            endTime: 3_000
        )
        let fixture = try makeFixture(transcriptionBehavior: .succeed([repairedResult]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.segments = [
            TranscriptSegment(
                speaker: "麦克风",
                text: "残缺实时转写",
                startTime: 0,
                endTime: 1_000,
                orderIndex: 0
            )
        ]
        meeting.lastAINotesTranscriptFingerprint = meeting.transcriptFingerprint
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.markTranscriptCoverageGap()

        let audioURL = try makeTemporaryAudioFile(named: "recording-repair-success.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 16,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.transcriptPipelineState == .ready)
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["完整补转写"])
        #expect(refreshedMeeting.enhancedNotes == "已有 AI 笔记")
        #expect(refreshedMeeting.aiNotesFreshnessState == .staleFromTranscript)
        #expect(fixture.transcriber.transcribeCalls == 1)
        #expect(fixture.syncService.syncedMeetingIDs == [meeting.id])
        #expect(fixture.syncService.transcriptSnapshotsAtSync == ["完整补转写"])
        #expect(fixture.recordingSessionStore.phase == .idle)
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)
        #expect(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id) == nil)
    }

    @MainActor
    @Test
    func stopRecordingWithCoverageGapMarksMeetingAsRepairingBeforeRepairCompletes() async throws {
        let fixture = try makeFixture(
            transcriptionBehavior: .succeed([
                ASRFinalResult(text: "完整补转写", startTime: 0, endTime: 2_000)
            ])
        )
        fixture.transcriber.shouldSuspendTranscription = true
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.markTranscriptCoverageGap()

        let audioURL = try makeTemporaryAudioFile(named: "recording-repair-stage.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let stopTask = Task { @MainActor in
            await fixture.meetingStore.finishStoppedRecording(
                meetingID: meeting.id,
                artifact: LocalAudioArtifact(
                    fileURL: audioURL,
                    durationSeconds: 8,
                    mimeType: "audio/m4a"
                )
            )
        }

        try await waitUntil { fixture.transcriber.transcribeCalls == 1 }

        let repairingMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(repairingMeeting.postStopProcessingStage == .repairingTranscript)
        #expect(fixture.recordingSessionStore.phase == .idle)

        fixture.transcriber.resumeTranscription()
        await stopTask.value
    }

    @MainActor
    @Test
    func loadIfNeededResumesPendingPostStopFinalization() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let recordingSessionStore = RecordingSessionStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let recorder = StubAudioRecorderService()
        let transcriber = StubAudioFileTranscriptionService(behavior: .succeed([]))
        let syncService = StubMeetingSyncService(repository: repository)
        let asrService = StubASRService()

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.status = .ended
        meeting.transcriptPipelineState = .ready
        meeting.syncState = .pending
        meeting.postStopProcessingStage = .finalizing
        meeting.markPending()
        try repository.save()

        let meetingStore = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: StubRecordingLiveActivityCoordinator(),
            audioRecorderService: recorder,
            audioFileTranscriptionService: transcriber,
            apiClient: apiClient,
            asrService: asrService,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService
        )

        meetingStore.loadIfNeeded()
        try await waitUntil { syncService.syncedMeetingIDs == [meeting.id] }

        let resumedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(resumedMeeting.postStopProcessingStage == .idle)
    }

    @MainActor
    @Test
    func recoveredForegroundAsrGapDoesNotTriggerStopTimeRepair() async throws {
        let fixture = try makeFixture(
            transcriptionBehavior: .succeed([
                ASRFinalResult(text: "不该再次补转写", startTime: 0, endTime: 1_000)
            ])
        )
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.status = .recording
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.asrState = .connected
        fixture.recordingSessionStore.durationSeconds = 6
        fixture.recorder.currentDurationSecondsValue = 6

        fixture.asrService.onError?("front fail")
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop)
        fixture.asrService.onFinalResult?(
            ASRFinalResult(text: "恢复后的最终转写", startTime: 2_000, endTime: 6_000)
        )
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)

        let audioURL = try makeTemporaryAudioFile(named: "recovered-foreground-gap.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 6,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.transcriptPipelineState == .ready)
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["恢复后的最终转写"])
        #expect(fixture.transcriber.transcribeCalls == 0)
        #expect(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id) == nil)
        #expect(fixture.meetingStore.fileTranscriptionPartial(meetingID: meeting.id).isEmpty)
    }

    @MainActor
    @Test
    func stopRecordingWithCoverageGapFailureDoesNotSyncOrGenerateAi() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .fail("repair failed"))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.segments = [
            TranscriptSegment(
                speaker: "麦克风",
                text: "残缺实时转写",
                startTime: 0,
                endTime: 1_000,
                orderIndex: 0
            )
        ]
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.markTranscriptCoverageGap()

        let audioURL = try makeTemporaryAudioFile(named: "recording-repair-failure.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 8,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.transcriptPipelineState == .refining)
        #expect(refreshedMeeting.speakerDiarizationState == .processing)
        #expect(refreshedMeeting.speakerDiarizationErrorMessage == "repair failed")
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["残缺实时转写"])
        #expect(fixture.syncService.syncedMeetingIDs.isEmpty)
        let status = try #require(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id))
        #expect(status.phase == .finalizing)
        #expect(status.canRetry == false)
        #expect(fixture.meetingStore.lastErrorMessage == "repair failed")
    }

    @MainActor
    @Test
    func interruptedRepairMeetingLoadsAsRecoverableEndedMeeting() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let recordingSessionStore = RecordingSessionStore()
        let apiClient = APIClient(settingsStore: settingsStore)
        let recorder = StubAudioRecorderService()
        let transcriber = StubAudioFileTranscriptionService(behavior: .succeed([]))
        let syncService = StubMeetingSyncService(repository: repository)
        let asrService = StubASRService()

        let audioURL = try makeTemporaryAudioFile(named: "interrupted-repair.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.status = .transcribing
        meeting.audioLocalPath = audioURL.path
        meeting.audioMimeType = "audio/m4a"
        meeting.audioDuration = 9
        meeting.speakerDiarizationState = .processing
        meeting.markPending()
        try repository.save()

        let meetingStore = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: StubRecordingLiveActivityCoordinator(),
            audioRecorderService: recorder,
            audioFileTranscriptionService: transcriber,
            apiClient: apiClient,
            asrService: asrService,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService
        )

        meetingStore.loadIfNeeded()

        let recoveredMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(recoveredMeeting.status == .ended)
        #expect(recoveredMeeting.transcriptPipelineState == .refining)
        #expect(recoveredMeeting.speakerDiarizationState == .processing)
        #expect(recoveredMeeting.syncState == .pending)
        let status = try #require(meetingStore.fileTranscriptionStatus(meetingID: meeting.id))
        #expect(status.phase == .finalizing)
        #expect(status.canRetry == false)
    }

    @MainActor
    @Test
    func generateAudioEnhancedNotesSyncsMeetingBeforeUploadingAudio() async throws {
        MeetingRecordingRepairMockURLProtocol.reset()
        defer { MeetingRecordingRepairMockURLProtocol.reset() }

        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.status = .ended
        meeting.title = "音频实验会议"
        meeting.audioMimeType = "audio/m4a"
        meeting.audioDuration = 12
        meeting.syncState = .pending

        let audioURL = try makeTemporaryAudioFile(named: "audio-notes-upload.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        meeting.audioLocalPath = audioURL.path
        try fixture.repository.save()

        MeetingRecordingRepairMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            switch url.path {
            case "/api/meetings/\(meeting.id)/audio":
                #expect(fixture.syncService.syncedMeetingIDs == [meeting.id])
                let payload: [String: Any] = [
                    "hasAudio": true,
                    "audioMimeType": "audio/m4a",
                    "audioDuration": 12,
                    "audioUpdatedAt": "2026-03-31T00:00:00.000Z",
                    "audioUrl": "/api/meetings/\(meeting.id)/audio?t=1",
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            case "/api/meetings/\(meeting.id)/ai-notes/audio":
                let payload: [String: Any]
                if request.httpMethod == "POST" {
                    payload = [
                        "meetingId": meeting.id,
                        "hasAudio": true,
                        "audioEnhancedNotes": "",
                        "audioEnhancedNotesStatus": "processing",
                        "audioEnhancedNotesError": "",
                        "audioEnhancedNotesUpdatedAt": NSNull(),
                        "audioEnhancedNotesProvider": NSNull(),
                        "audioEnhancedNotesModel": NSNull(),
                        "audioEnhancedNotesAttempts": 1,
                        "audioEnhancedNotesRequestedAt": "2026-03-31T00:00:01.000Z",
                        "audioEnhancedNotesStartedAt": NSNull(),
                    ]
                } else {
                    payload = [
                        "meetingId": meeting.id,
                        "hasAudio": true,
                        "audioEnhancedNotes": "## 会议摘要\n- 已根据原始音频生成",
                        "audioEnhancedNotesStatus": "ready",
                        "audioEnhancedNotesError": "",
                        "audioEnhancedNotesUpdatedAt": "2026-03-31T00:00:02.000Z",
                        "audioEnhancedNotesProvider": "test",
                        "audioEnhancedNotesModel": "gemini-3-flash-preview",
                        "audioEnhancedNotesAttempts": 1,
                        "audioEnhancedNotesRequestedAt": "2026-03-31T00:00:01.000Z",
                        "audioEnhancedNotesStartedAt": "2026-03-31T00:00:01.500Z",
                    ]
                }
                return (response, try JSONSerialization.data(withJSONObject: payload))

            default:
                throw URLError(.badURL)
            }
        }

        await fixture.meetingStore.generateAudioEnhancedNotes(for: meeting.id)

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(fixture.syncService.syncedMeetingIDs == [meeting.id])
        #expect(refreshedMeeting.audioEnhancedNotesStatus == .ready)
        #expect(refreshedMeeting.audioEnhancedNotes.contains("已根据原始音频生成"))
        #expect(refreshedMeeting.audioRemotePath?.contains("/api/meetings/\(meeting.id)/audio") == true)
    }

    @MainActor
    private func makeFixture(
        transcriptionBehavior: StubAudioFileTranscriptionService.Behavior
    ) throws -> (
        container: ModelContainer,
        meetingStore: MeetingStore,
        repository: MeetingRepository,
        settingsStore: SettingsStore,
        recordingSessionStore: RecordingSessionStore,
        recorder: StubAudioRecorderService,
        asrService: StubASRService,
        transcriber: StubAudioFileTranscriptionService,
        syncService: StubMeetingSyncService,
        liveActivity: StubRecordingLiveActivityCoordinator
    ) {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let recordingSessionStore = RecordingSessionStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let recorder = StubAudioRecorderService()
        let transcriber = StubAudioFileTranscriptionService(behavior: transcriptionBehavior)
        let syncService = StubMeetingSyncService(repository: repository)
        let asrService = StubASRService()
        let liveActivity = StubRecordingLiveActivityCoordinator()
        let meetingStore = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: liveActivity,
            audioRecorderService: recorder,
            audioFileTranscriptionService: transcriber,
            apiClient: apiClient,
            asrService: asrService,
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService
        )
        return (
            container,
            meetingStore,
            repository,
            settingsStore,
            recordingSessionStore,
            recorder,
            asrService,
            transcriber,
            syncService,
            liveActivity
        )
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.recording.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
    }

    @MainActor
    private func makeAPIClient(settingsStore: SettingsStore) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeetingRecordingRepairMockURLProtocol.self]
        return APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )
    }

    private func makeTemporaryAudioFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: url)
        return url
    }

    private func makePCMChunk(durationMS: Int) -> Data {
        let bytesPerMillisecond = (Double(Int(PCMConverter.targetSampleRate)) * 2) / 1000
        let byteCount = Int((Double(durationMS) * bytesPerMillisecond).rounded())
        return Data(repeating: 0, count: max(byteCount, 0))
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw URLError(.badServerResponse)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)

            if bytesRead < 0 {
                throw stream.streamError ?? URLError(.cannotParseResponse)
            }

            if bytesRead == 0 {
                break
            }

            data.append(contentsOf: buffer.prefix(bytesRead))
        }

        return data
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(timeoutNanoseconds)
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("Condition timed out")
                throw CancellationError()
            }
            await Task.yield()
        }
    }
}
