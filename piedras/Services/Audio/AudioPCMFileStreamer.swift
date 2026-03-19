import AVFoundation
import Foundation

enum AudioPCMFileStreamer {
    static func pcmChunkStream(
        from fileURL: URL,
        chunkFrameCount: AVAudioFrameCount = 4_096
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let audioFile = try AVAudioFile(forReading: fileURL)
                    guard let buffer = AVAudioPCMBuffer(
                        pcmFormat: audioFile.processingFormat,
                        frameCapacity: chunkFrameCount
                    ) else {
                        throw AudioSessionError.recorderUnavailable
                    }

                    while true {
                        try audioFile.read(into: buffer)
                        guard buffer.frameLength > 0 else {
                            break
                        }

                        if let chunk = PCMConverter.downsampledPCMData(from: buffer), !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
