import Foundation

enum StreamTextReader {
    static func stream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await consume(bytes: bytes) { accumulated in
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func collect(from bytes: URLSession.AsyncBytes) async throws -> String {
        try await consume(bytes: bytes, onUpdate: nil)
    }

    private static func consume(
        bytes: URLSession.AsyncBytes,
        onUpdate: ((String) -> Void)?
    ) async throws -> String {
        var accumulated = ""
        var pendingBytes: [UInt8] = []

        for try await byte in bytes {
            pendingBytes.append(byte)
            if let fragment = String(bytes: pendingBytes, encoding: .utf8) {
                pendingBytes.removeAll(keepingCapacity: true)
                accumulated += fragment
                onUpdate?(accumulated)
            }
        }

        if !pendingBytes.isEmpty, let trailing = String(bytes: pendingBytes, encoding: .utf8) {
            accumulated += trailing
            onUpdate?(accumulated)
        }

        return accumulated
    }
}
