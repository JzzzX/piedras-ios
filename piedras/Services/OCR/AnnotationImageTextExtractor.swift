import Foundation
import ImageIO
import Vision

protocol AnnotationImageTextExtracting: Sendable {
    func extractText(from imageURLs: [URL]) async throws -> String
}

struct VisionAnnotationImageTextExtractor: AnnotationImageTextExtracting {
    nonisolated init() {}

    nonisolated func extractText(from imageURLs: [URL]) async throws -> String {
        try await Task.detached(priority: .utility) {
            try Self.extractTextSynchronously(from: imageURLs)
        }.value
    }

    private nonisolated static func extractTextSynchronously(from imageURLs: [URL]) throws -> String {
        var sections: [String] = []
        var lastError: Error?

        for (index, url) in imageURLs.enumerated() {
            do {
                let recognizedText = try recognizeText(from: url)
                let trimmed = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if imageURLs.count > 1 {
                    sections.append("图片\(index + 1)：\n\(trimmed)")
                } else {
                    sections.append(trimmed)
                }
            } catch {
                lastError = error
            }
        }

        if sections.isEmpty, let lastError {
            throw lastError
        }

        return sections.joined(separator: "\n\n")
    }

    private nonisolated static func recognizeText(from url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.orderedUnique().joined(separator: "\n")
    }
}

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
