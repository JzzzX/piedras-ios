import Testing
@testable import CocoInterview

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
            hasEnhancedNotes: false,
            hasDisplayableTranscript: false
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
            hasEnhancedNotes: false,
            hasDisplayableTranscript: false
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
            hasEnhancedNotes: false,
            hasDisplayableTranscript: false
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
            hasEnhancedNotes: false,
            hasDisplayableTranscript: false
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
            hasEnhancedNotes: false,
            hasDisplayableTranscript: false
        )

        #expect(state.usesRecordingWorkspace == false)
        #expect(state.showsEnhancedNotesProcessing == true)
        #expect(state.transcriptionStatus == nil)
    }

    @Test
    func enhancingExistingNotesShowsRefreshHintInsteadOfProcessingPlaceholder() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: nil,
            recordingPhase: .idle,
            postStopProcessingStage: .idle,
            transcriptionStatus: nil,
            isEnhancing: true,
            hasEnhancedNotes: true,
            hasDisplayableTranscript: true
        )

        #expect(state.showsEnhancedNotesProcessing == false)
        #expect(state.showsEnhancedNotesRefreshHint == true)
        #expect(state.transcriptionStatus == nil)
    }

    @Test
    func existingTranscriptSuppressesSyntheticFinalizingStatusAfterStop() {
        let state = MeetingDetailPresentationState(
            meetingID: "meeting-1",
            recordingSessionMeetingID: nil,
            recordingPhase: .idle,
            postStopProcessingStage: .finalizing,
            transcriptionStatus: nil,
            isEnhancing: false,
            hasEnhancedNotes: true,
            hasDisplayableTranscript: true
        )

        #expect(state.transcriptionStatus == nil)
    }
}
