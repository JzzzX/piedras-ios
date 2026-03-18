import AVFoundation
import Foundation

enum AudioSessionError: LocalizedError {
    case microphonePermissionDenied
    case recorderUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝，请在系统设置中允许 Piedras 访问麦克风。"
        case .recorderUnavailable:
            return "录音器不可用，请稍后重试。"
        }
    }
}

@MainActor
final class AudioSessionCoordinator {
    private let session = AVAudioSession.sharedInstance()

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func configureForRecording(allowsFilePlayback: Bool = false) throws {
        try session.setCategory(
            .playAndRecord,
            mode: allowsFilePlayback ? .default : .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
