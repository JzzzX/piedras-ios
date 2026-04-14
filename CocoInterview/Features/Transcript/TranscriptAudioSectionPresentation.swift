import Foundation

enum TranscriptAudioSectionMode: Equatable {
    case hidden
    case recordingNotice
    case player(URL)
}

enum TranscriptAudioSectionPresentation {
    static func mode(for meeting: Meeting, isActiveRecording: Bool) -> TranscriptAudioSectionMode {
        if isActiveRecording {
            return .recordingNotice
        }

        if let localPath = meeting.audioLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           FileManager.default.fileExists(atPath: localPath),
           !localPath.isEmpty {
            return .player(URL(fileURLWithPath: localPath))
        }

        if let remoteURLString = meeting.audioRemotePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           let remoteURL = URL(string: remoteURLString),
           !remoteURLString.isEmpty {
            return .player(remoteURL)
        }

        return .hidden
    }
}
