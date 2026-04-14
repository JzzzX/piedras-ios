import Foundation
import Testing
@testable import CocoInterview

struct AudioFileResolverTests {
    @Test
    func prefersExistingLocalAudioFile() async throws {
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-local-\(UUID().uuidString).m4a")
        try Data("local-audio".utf8).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        var didCallRemoteLoader = false
        let resolvedURL = try await AudioFileResolver.resolveFileURL(
            localPath: localURL.path,
            remoteURLString: "https://example.com/api/meetings/meeting-1/audio",
            remoteDataLoader: { _ in
                didCallRemoteLoader = true
                return Data()
            }
        )

        #expect(resolvedURL == localURL)
        #expect(didCallRemoteLoader == false)
    }

    @Test
    func downloadsRemoteAudioIntoTemporaryCacheFile() async throws {
        let remoteURLString = "https://example.com/api/meetings/meeting-2/audio"
        var requestedURL: URL?

        let resolvedURL = try await AudioFileResolver.resolveFileURL(
            localPath: nil,
            remoteURLString: remoteURLString,
            remoteDataLoader: { remoteURL in
                requestedURL = remoteURL
                return Data("remote-audio".utf8)
            }
        )
        defer { try? FileManager.default.removeItem(at: resolvedURL) }

        #expect(requestedURL?.absoluteString == remoteURLString)
        #expect(FileManager.default.fileExists(atPath: resolvedURL.path))
        let savedData = try Data(contentsOf: resolvedURL)
        #expect(String(decoding: savedData, as: UTF8.self) == "remote-audio")
    }
}
