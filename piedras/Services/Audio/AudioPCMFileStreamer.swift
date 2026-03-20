import AVFoundation
import Foundation

enum AudioPCMFileStreamer {
    enum Backend {
        case avAudioFile
        case assetReader
    }

    static func pcmChunkStream(
        from fileURL: URL,
        backend: Backend = .avAudioFile,
        chunkFrameCount: AVAudioFrameCount = 4_096
    ) -> AsyncThrowingStream<Data, Error> {
        switch backend {
        case .avAudioFile:
            return pcmChunkStreamUsingAVAudioFile(from: fileURL, chunkFrameCount: chunkFrameCount)
        case .assetReader:
            return pcmChunkStreamUsingAssetReader(from: fileURL)
        }
    }

    private static func pcmChunkStreamUsingAVAudioFile(
        from fileURL: URL,
        chunkFrameCount: AVAudioFrameCount
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

    private static func pcmChunkStreamUsingAssetReader(
        from fileURL: URL
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let asset = AVURLAsset(url: fileURL)
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard let track = tracks.first else {
                        throw AudioFileTranscriptionError.unreadableAudioFile
                    }

                    let outputSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: PCMConverter.targetSampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false,
                    ]

                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                    output.alwaysCopiesSampleData = false

                    guard reader.canAdd(output) else {
                        throw AudioFileTranscriptionError.audioDecodingFailed("AVAssetReader 无法添加音轨输出。")
                    }

                    reader.add(output)

                    guard reader.startReading() else {
                        throw reader.error ?? AudioFileTranscriptionError.unreadableAudioFile
                    }

                    while reader.status == .reading {
                        guard let sampleBuffer = output.copyNextSampleBuffer() else {
                            break
                        }

                        defer { CMSampleBufferInvalidate(sampleBuffer) }

                        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                           let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
                            guard Int(streamDescription.mChannelsPerFrame) == 1 else {
                                throw AudioFileTranscriptionError.audioDecodingFailed("规范化音频声道数异常。")
                            }

                            guard abs(streamDescription.mSampleRate - PCMConverter.targetSampleRate) < 1 else {
                                throw AudioFileTranscriptionError.audioDecodingFailed("规范化音频采样率异常。")
                            }
                        }

                        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                            continue
                        }

                        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
                        guard dataLength > 0 else {
                            continue
                        }

                        var data = Data(count: dataLength)
                        let status = data.withUnsafeMutableBytes { rawBuffer in
                            guard let baseAddress = rawBuffer.baseAddress else {
                                return OSStatus(-12731)
                            }

                            return CMBlockBufferCopyDataBytes(
                                blockBuffer,
                                atOffset: 0,
                                dataLength: dataLength,
                                destination: baseAddress
                            )
                        }

                        guard status == kCMBlockBufferNoErr else {
                            throw AudioFileTranscriptionError.audioDecodingFailed("读取规范化 PCM 数据失败。")
                        }

                        continuation.yield(data)
                    }

                    switch reader.status {
                    case .completed:
                        continuation.finish()
                    case .failed:
                        continuation.finish(
                            throwing: reader.error ?? AudioFileTranscriptionError.unreadableAudioFile
                        )
                    case .cancelled:
                        continuation.finish(throwing: CancellationError())
                    default:
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
