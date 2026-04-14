import Foundation
import Testing
@testable import CocoInterview

struct AudioFileTranscriptionServiceTests {
    @Test
    func liveAsrReadyGateTimesOutWithoutReadySignal() async throws {
        let gate = ASRReadyGate()

        await #expect(throws: Error.self) {
            try await gate.waitUntilReady(timeout: .milliseconds(50))
        }
    }

    @Test
    func liveAsrReadyGateCompletesAfterReadySignal() async throws {
        let gate = ASRReadyGate()

        let waiter = Task {
            try await gate.waitUntilReady(timeout: .seconds(1))
        }

        try await Task.sleep(for: .milliseconds(20))
        await gate.markReady()
        try await waiter.value
    }

    @Test
    func liveAsrBufferPolicyFlagsOverflowWhenIncomingAudioExceedsCap() {
        #expect(
            ASRBufferPolicy.shouldFailPendingBuffer(
                currentBufferedBytes: 30_000,
                incomingBytes: 2_001,
                maxBufferedBytes: 32_000
            )
        )
        #expect(
            ASRBufferPolicy.shouldFailPendingBuffer(
                currentBufferedBytes: 30_000,
                incomingBytes: 2_000,
                maxBufferedBytes: 32_000
            ) == false
        )
    }

    @Test
    func treatsPostStopNormalCloseAsGracefulCompletion() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: false,
            didReceiveTranscriptText: false,
            didEmitFinalResult: false,
            closeCode: .normalClosure
        )

        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 57,
            userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .finishGracefully
        )
    }

    @Test
    func keepsPreStopSocketDisconnectAsFailure() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: false,
            didReceiveServiceError: false,
            didReceiveTranscriptText: false,
            didEmitFinalResult: false,
            closeCode: .invalid
        )

        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 57,
            userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .fail
        )
    }

    @Test
    func keepsPostStopServiceErrorsAsFailures() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: true,
            didReceiveTranscriptText: true,
            didEmitFinalResult: true,
            closeCode: .normalClosure
        )

        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 57,
            userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .fail
        )
    }

    @Test
    func keepsFinalizationTimeoutAsFailure() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: false,
            didReceiveTranscriptText: false,
            didEmitFinalResult: false,
            closeCode: .normalClosure
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(
                AudioFileTranscriptionError.timedOut,
                context: context
            ) == .fail
        )
    }

    @Test
    func treatsGoingAwayCloseDuringFinalizationAsGracefulCompletion() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: false,
            didReceiveTranscriptText: false,
            didEmitFinalResult: false,
            closeCode: .goingAway
        )

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .finishGracefully
        )
    }

    @Test
    func treatsAbruptCloseAfterFinalResultsAsGracefulCompletion() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: false,
            didReceiveTranscriptText: true,
            didEmitFinalResult: true,
            closeCode: .invalid
        )

        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 57,
            userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .finishGracefully
        )
    }

    @Test
    func keepsAbruptCloseWithoutFinalResultsAsFailure() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: false,
            didReceiveTranscriptText: false,
            didEmitFinalResult: false,
            closeCode: .invalid
        )

        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 57,
            userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .fail
        )
    }

    @Test
    func treatsAbruptCloseAfterPartialResultsAsGracefulCompletion() {
        let context = AudioFileTranscriptionTransportFailureContext(
            didBeginFinalization: true,
            didReceiveServiceError: false,
            didReceiveTranscriptText: true,
            didEmitFinalResult: false,
            closeCode: .noStatusReceived
        )

        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 57,
            userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
        )

        #expect(
            AudioFileTranscriptionService.classifyTransportFailure(error, context: context)
                == .finishGracefully
        )
    }

    @Test
    func mapsGenericObjCAudioFailuresToFriendlyMessage() {
        let error = NSError(
            domain: "Foundation._GenericObjCError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (Foundation._GenericObjCError error 0.)"]
        )

        let message = AudioFileTranscriptionService.userVisibleAudioProcessingMessage(
            for: error,
            fallback: "fallback"
        )

        #expect(message.contains("m4a"))
        #expect(!message.contains("GenericObjCError"))
    }
}
