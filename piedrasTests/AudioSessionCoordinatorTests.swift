import AVFoundation
import Testing
@testable import piedras

@Suite(.serialized)
struct AudioSessionCoordinatorTests {
    @MainActor
    @Test
    func recordingConfigurationAllowsSystemHapticsDuringRecording() throws {
        let session = AVAudioSession.sharedInstance()
        let coordinator = AudioSessionCoordinator()

        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker]
        )
        try session.setAllowHapticsAndSystemSoundsDuringRecording(false)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        try coordinator.configureForRecording()

        #expect(session.category == .playAndRecord)
        #expect(session.allowHapticsAndSystemSoundsDuringRecording)

        coordinator.deactivate()
    }
}
