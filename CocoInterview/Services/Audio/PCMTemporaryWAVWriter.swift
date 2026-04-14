import Foundation

enum PCMTemporaryWAVWriter {
    static func write(
        pcmData: Data,
        sampleRate: Int = Int(PCMConverter.targetSampleRate),
        channels: Int = 1
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("coco-interview-background-gap", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let fileData = makeWAVHeader(
            dataByteCount: pcmData.count,
            sampleRate: sampleRate,
            channels: channels
        ) + pcmData

        try fileData.write(to: url, options: .atomic)
        return url
    }

    private static func makeWAVHeader(
        dataByteCount: Int,
        sampleRate: Int,
        channels: Int
    ) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let riffChunkSize = 36 + dataByteCount

        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        header.append(contentsOf: littleEndianBytes(UInt32(riffChunkSize)))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        header.append(contentsOf: littleEndianBytes(UInt32(16)))
        header.append(contentsOf: littleEndianBytes(UInt16(1)))
        header.append(contentsOf: littleEndianBytes(UInt16(channels)))
        header.append(contentsOf: littleEndianBytes(UInt32(sampleRate)))
        header.append(contentsOf: littleEndianBytes(UInt32(byteRate)))
        header.append(contentsOf: littleEndianBytes(UInt16(blockAlign)))
        header.append(contentsOf: littleEndianBytes(UInt16(bitsPerSample)))
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        header.append(contentsOf: littleEndianBytes(UInt32(dataByteCount)))
        return header
    }

    private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}
