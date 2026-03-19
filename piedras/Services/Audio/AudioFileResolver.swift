import Foundation

enum AudioFileResolverError: LocalizedError {
    case missingAudioSource
    case invalidRemoteURL

    var errorDescription: String? {
        switch self {
        case .missingAudioSource:
            return "没有可用的音频文件。"
        case .invalidRemoteURL:
            return "远端音频地址无效。"
        }
    }
}

enum AudioFileResolver {
    static func resolveFileURL(for meeting: Meeting) async throws -> URL {
        try await resolveFileURL(
            localPath: meeting.audioLocalPath,
            remoteURLString: meeting.audioRemotePath
        )
    }

    static func resolveFileURL(localPath: String?, remoteURLString: String?) async throws -> URL {
        if let localPath,
           FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }

        guard let remoteURLString, !remoteURLString.isEmpty else {
            throw AudioFileResolverError.missingAudioSource
        }

        guard let remoteURL = URL(string: remoteURLString) else {
            throw AudioFileResolverError.invalidRemoteURL
        }

        return try await downloadRemoteAudio(from: remoteURL)
    }

    private static func downloadRemoteAudio(from remoteURL: URL) async throws -> URL {
        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piedras-audio-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileExtension = remoteURL.pathExtension.isEmpty ? "audio" : remoteURL.pathExtension
        let destinationURL = directoryURL.appendingPathComponent("\(UUID().uuidString.lowercased()).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }
}
