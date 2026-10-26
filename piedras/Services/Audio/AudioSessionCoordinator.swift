import AVFoundation
import Foundation

enum AudioSessionLifecycleEvent: Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool, wasSuspended: Bool)
    case routeChanged(reason: AVAudioSession.RouteChangeReason)
    case mediaServicesWereLost
    case mediaServicesWereReset
}

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
    private let notificationCenter: NotificationCenter
    private var observerTokens: [NSObjectProtocol] = []

    var onLifecycleEvent: ((AudioSessionLifecycleEvent) -> Void)?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        registerObservers()
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }

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
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func registerObservers() {
        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruptionNotification(notification)
            }
        )

        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChangeNotification(notification)
            }
        )

        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.mediaServicesWereLostNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.onLifecycleEvent?(.mediaServicesWereLost)
            }
        )

        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.onLifecycleEvent?(.mediaServicesWereReset)
            }
        )
    }

    private func handleInterruptionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            onLifecycleEvent?(.interruptionBegan)
        case .ended:
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            let wasSuspended = (userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? Bool) ?? false
            onLifecycleEvent?(
                .interruptionEnded(
                    shouldResume: options.contains(.shouldResume),
                    wasSuspended: wasSuspended
                )
            )
        @unknown default:
            break
        }
    }

    private func handleRouteChangeNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }

        onLifecycleEvent?(.routeChanged(reason: reason))
    }
}
