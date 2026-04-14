import Foundation
import Testing
@testable import CocoInterview

struct UserVisibleMediaErrorFormatterTests {
    @Test
    func keepsImportPreparationFailuresMappedToReexportGuidance() {
        let message = UserVisibleMediaErrorFormatter.transcriptionImportFailureDetail(
            from: "The operation couldn’t be completed. (Foundation._GenericObjCError error 0.)",
            fallback: AppStrings.current.audioFileNeedsReexport
        )

        #expect(message == AppStrings.current.audioFileNeedsReexport)
    }

    @Test
    func mapsTransportFailuresToConnectionGuidanceInsteadOfReexport() {
        let message = UserVisibleMediaErrorFormatter.transcriptionTransportFailureDetail(
            from: "The network connection was lost.",
            fallback: AppStrings.current.audioTranscriptionConnectionIssue
        )

        #expect(message == AppStrings.current.audioTranscriptionConnectionIssue)
        #expect(message != AppStrings.current.audioFileNeedsReexport)
    }

    @Test
    func mapsTechnicalServiceFailuresToTemporaryServiceMessage() {
        let message = UserVisibleMediaErrorFormatter.transcriptionServiceFailureDetail(
            from: "Foundation.CustomDomain code=7 [RID: 1234-5678] backend exploded unexpectedly",
            fallback: AppStrings.current.audioTranscriptionServiceUnavailable
        )

        #expect(message == AppStrings.current.audioTranscriptionServiceUnavailable)
    }

    @Test
    func mapsSilentAudioToFriendlyTranscriptionDetail() {
        let message = UserVisibleMediaErrorFormatter.transcriptionFailureDetail(
            from: "上传会议音频失败：离线转写失败：[Normal silence audio] no valid speech in audio [RID: 123]"
        )

        #expect(message == AppStrings.current.noSpeechDetectedInAudio)
    }

    @Test
    func hidesUnknownTechnicalTranscriptionDetails() {
        let message = UserVisibleMediaErrorFormatter.transcriptionFailureDetail(
            from: "Foundation.CustomDomain code=7 [RID: 1234-5678] backend exploded unexpectedly"
        )

        #expect(message == nil)
    }

    @Test
    func failedStatusStillAllowsRetryWithoutDetailBody() {
        let status = FileTranscriptionStatusSnapshot(
            phase: nil,
            errorMessage: nil,
            showsFailure: true
        )

        #expect(status.canRetry)
        #expect(status.displayMessage == AppStrings.current.audioTranscriptionFailed)
    }

    @Test
    func mapsPlaybackOsStatusFailureToFriendlyMessage() {
        let error = NSError(
            domain: NSOSStatusErrorDomain,
            code: -50,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (OSStatus error -50.)"]
        )

        let message = UserVisibleMediaErrorFormatter.playbackFailureMessage(for: error)

        #expect(message == AppStrings.current.audioPlaybackFailed)
    }
}
