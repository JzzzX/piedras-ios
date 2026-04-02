import Testing
@testable import piedras

struct MeetingDetailPresentationStateTests {
    @Test
    func stoppingPhaseLeavesRecordingWorkspaceImmediately() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: "meeting-1",
            recordingPhase: .stopping,
            postStopProcessingStage: .idle,
            transcriptionStatus: nil,
            isEnhancing: false,
            hasEnhancedNotes: false
        )

        #expect(state.usesRecordingWorkspace == false)
    }

    @Test
    func stoppingPhaseSynthesizesFinalizingStatusBeforePersistenceCatchesUp() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: "meeting-1",
            recordingPhase: .stopping,
            postStopProcessingStage: .idle,
            transcriptionStatus: nil,
            isEnhancing: false,
            hasEnhancedNotes: false
        )

        #expect(state.transcriptionStatus?.phase == .finalizing)
        #expect(state.transcriptionStatus?.canRetry == false)
    }

    @Test
    func stoppingPhaseForcesProcessingPlaceholderWhileAiNotesAreStillEmpty() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: "meeting-1",
            recordingPhase: .stopping,
            postStopProcessingStage: .idle,
            transcriptionStatus: nil,
            isEnhancing: false,
            hasEnhancedNotes: false
        )

        #expect(state.showsEnhancedNotesProcessing == true)
    }

    @Test
    func existingTranscriptionStatusWinsOverSyntheticStoppingState() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: "meeting-1",
            recordingPhase: .stopping,
            postStopProcessingStage: .idle,
            transcriptionStatus: FileTranscriptionStatusSnapshot(
                phase: .connecting,
                errorMessage: nil
            ),
            isEnhancing: false,
            hasEnhancedNotes: false
        )

        #expect(state.transcriptionStatus?.phase == .connecting)
    }

    @Test
    func persistedPostStopProcessingKeepsProcessingPlaceholderAfterRecordingSessionResets() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: nil,
            recordingPhase: .idle,
            postStopProcessingStage: .finalizing,
            transcriptionStatus: nil,
            isEnhancing: false,
            hasEnhancedNotes: false
        )

        #expect(state.usesRecordingWorkspace == false)
        #expect(state.showsEnhancedNotesProcessing == true)
        #expect(state.transcriptionStatus?.phase == .finalizing)
    }
}
