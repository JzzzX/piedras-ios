import AVFoundation
import Foundation

enum PCMConverter {
    nonisolated static let targetSampleRate: Double = 16_000

    nonisolated static func downsampledPCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let monoSamples = makeMonoFloat32Samples(from: buffer) else {
            return nil
        }

        let downsampled = downsample(samples: monoSamples, inputSampleRate: buffer.format.sampleRate)
        return makeInt16PCMData(from: downsampled)
    }

    nonisolated static func normalizedRMSLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let monoSamples = makeMonoFloat32Samples(from: buffer), !monoSamples.isEmpty else {
            return 0
        }

        let squareSum = monoSamples.reduce(Float.zero) { partial, sample in
            partial + sample * sample
        }

        let rms = sqrt(squareSum / Float(monoSamples.count))
        return max(0, min(Double(rms) * 3.2, 1))
    }

    private nonisolated static func makeMonoFloat32Samples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard channelCount > 0, frameLength > 0 else {
            return []
        }

        if let channelData = buffer.floatChannelData {
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }

            var output = Array(repeating: Float.zero, count: frameLength)
            for channelIndex in 0 ..< channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channelIndex], count: frameLength)
                for frameIndex in 0 ..< frameLength {
                    output[frameIndex] += samples[frameIndex]
                }
            }

            let divisor = Float(channelCount)
            for frameIndex in 0 ..< frameLength {
                output[frameIndex] /= divisor
            }

            return output
        }

        if let int16ChannelData = buffer.int16ChannelData {
            if channelCount == 1 {
                let samples = UnsafeBufferPointer(start: int16ChannelData[0], count: frameLength)
                return samples.map { Float($0) / Float(Int16.max) }
            }

            var output = Array(repeating: Float.zero, count: frameLength)
            for channelIndex in 0 ..< channelCount {
                let samples = UnsafeBufferPointer(start: int16ChannelData[channelIndex], count: frameLength)
                for frameIndex in 0 ..< frameLength {
                    output[frameIndex] += Float(samples[frameIndex]) / Float(Int16.max)
                }
            }

            let divisor = Float(channelCount)
            for frameIndex in 0 ..< frameLength {
                output[frameIndex] /= divisor
            }

            return output
        }

        if let int32ChannelData = buffer.int32ChannelData {
            if channelCount == 1 {
                let samples = UnsafeBufferPointer(start: int32ChannelData[0], count: frameLength)
                return samples.map { Float($0) / Float(Int32.max) }
            }

            var output = Array(repeating: Float.zero, count: frameLength)
            for channelIndex in 0 ..< channelCount {
                let samples = UnsafeBufferPointer(start: int32ChannelData[channelIndex], count: frameLength)
                for frameIndex in 0 ..< frameLength {
                    output[frameIndex] += Float(samples[frameIndex]) / Float(Int32.max)
                }
            }

            let divisor = Float(channelCount)
            for frameIndex in 0 ..< frameLength {
                output[frameIndex] /= divisor
            }

            return output
        }

        return nil
    }

    private nonisolated static func downsample(samples: [Float], inputSampleRate: Double) -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        guard inputSampleRate != targetSampleRate else {
            return samples
        }

        let ratio = inputSampleRate / targetSampleRate
        let outputLength = max(1, Int(round(Double(samples.count) / ratio)))
        var output = Array(repeating: Float.zero, count: outputLength)

        var outputIndex = 0
        var inputOffset = 0

        while outputIndex < outputLength {
            let nextInputOffset = min(samples.count, Int(round(Double(outputIndex + 1) * ratio)))
            let upperBound = max(inputOffset + 1, nextInputOffset)

            var sum: Float = 0
            var count = 0

            for inputIndex in inputOffset ..< min(upperBound, samples.count) {
                sum += samples[inputIndex]
                count += 1
            }

            output[outputIndex] = count > 0 ? sum / Float(count) : 0
            outputIndex += 1
            inputOffset = upperBound
        }

        return output
    }

    private nonisolated static func makeInt16PCMData(from samples: [Float]) -> Data {
        var pcm = Array(repeating: Int16.zero, count: samples.count)
        for index in samples.indices {
            let sample = max(-1, min(1, samples[index]))
            pcm[index] = sample < 0 ? Int16(sample * 0x8000) : Int16(sample * 0x7fff)
        }

        return pcm.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }
    }
}
