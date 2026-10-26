import Foundation
import Testing
@testable import piedras

@MainActor
struct TranscriptAudioPresentationTests {
    @Test
    func activeRecordingShowsRecordingNoticeEvenWhenLocalAudioExists() {
        let meeting = Meeting(audioLocalPath: "/tmp/recording.m4a")

        #expect(
            TranscriptAudioSectionPresentation.mode(
                for: meeting,
                isActiveRecording: true
            ) == .recordingNotice
        )
    }

    @Test
    func endedMeetingShowsPlayerForLocalAudio() {
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        _ = FileManager.default.createFile(atPath: localURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: localURL) }

        let meeting = Meeting(audioLocalPath: localURL.path)

        #expect(
            TranscriptAudioSectionPresentation.mode(
                for: meeting,
                isActiveRecording: false
            ) == .player(localURL)
        )
    }

    @Test
    func endedMeetingFallsBackToRemoteAudioWhenLocalFileIsMissing() {
        let meeting = Meeting(
            audioLocalPath: "/tmp/missing-recording.m4a",
            audioRemotePath: "https://example.com/audio/meeting.m4a"
        )

        #expect(
            TranscriptAudioSectionPresentation.mode(
                for: meeting,
                isActiveRecording: false
            ) == .player(URL(string: "https://example.com/audio/meeting.m4a")!)
        )
    }

    @Test
    func noAudioSourceHidesSectionWhenNotRecording() {
        let meeting = Meeting()

        #expect(
            TranscriptAudioSectionPresentation.mode(
                for: meeting,
                isActiveRecording: false
            ) == .hidden
        )
    }
}
