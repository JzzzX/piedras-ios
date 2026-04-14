import Foundation

enum UserVisibleMediaErrorFormatter {
    nonisolated static func transcriptionFailureDetail(from rawMessage: String?) -> String? {
        friendlyMessage(
            from: rawMessage,
            technicalFallback: nil,
            genericAudioFallback: currentStrings.audioFileNeedsReexport
        )
    }

    nonisolated static func transcriptionImportFailureDetail(
        from rawMessage: String?,
        fallback: String
    ) -> String {
        friendlyMessage(
            from: rawMessage,
            technicalFallback: fallback,
            genericAudioFallback: fallback
        )
        ?? fallback
    }

    nonisolated static func transcriptionTransportFailureDetail(
        from rawMessage: String?,
        fallback: String
    ) -> String {
        categorizedFailureMessage(
            from: rawMessage,
            fallback: fallback,
            treatRecognizedTransportIssuesAsFallback: true
        )
    }

    nonisolated static func transcriptionServiceFailureDetail(
        from rawMessage: String?,
        fallback: String
    ) -> String {
        categorizedFailureMessage(
            from: rawMessage,
            fallback: fallback,
            treatRecognizedTransportIssuesAsFallback: false
        )
    }

    nonisolated static func playbackFailureMessage(for error: Error?) -> String? {
        friendlyMessage(
            from: (error as NSError?)?.localizedDescription,
            technicalFallback: currentStrings.audioPlaybackFailed,
            genericAudioFallback: currentStrings.audioPlaybackFailed
        )
    }

    private nonisolated static var currentStrings: AppStringTable {
        AppStringTable(language: AppStrings.currentLanguage)
    }

    private nonisolated static func categorizedFailureMessage(
        from rawMessage: String?,
        fallback: String,
        treatRecognizedTransportIssuesAsFallback: Bool
    ) -> String {
        guard let rawMessage else {
            return fallback
        }

        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }

        let normalized = trimmed.lowercased()

        if normalized.contains("normal silence audio") || normalized.contains("no valid speech in audio") {
            return currentStrings.noSpeechDetectedInAudio
        }

        if treatRecognizedTransportIssuesAsFallback && looksLikeTransportIssue(normalized) {
            return fallback
        }

        if normalized.contains("genericobjcerror")
            || normalized.contains("operation couldn")
            || normalized.contains("osstatus error")
            || normalized.contains("avfoundationerrordomain")
            || looksTechnical(trimmed, normalized: normalized) {
            return fallback
        }

        return trimmed
    }

    private nonisolated static func friendlyMessage(
        from rawMessage: String?,
        technicalFallback: String?,
        genericAudioFallback: String
    ) -> String? {
        guard let rawMessage else {
            return technicalFallback
        }

        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return technicalFallback
        }

        let normalized = trimmed.lowercased()

        if normalized.contains("normal silence audio") || normalized.contains("no valid speech in audio") {
            return currentStrings.noSpeechDetectedInAudio
        }

        if normalized.contains("genericobjcerror")
            || normalized.contains("operation couldn")
            || normalized.contains("osstatus error")
            || normalized.contains("avfoundationerrordomain")
        {
            return genericAudioFallback
        }

        if looksTechnical(trimmed, normalized: normalized) {
            return technicalFallback
        }

        return trimmed
    }

    private nonisolated static func looksTechnical(_ rawMessage: String, normalized: String) -> Bool {
        if rawMessage.count > 72 {
            return true
        }

        let technicalMarkers = [
            "[rid:",
            " code=",
            " domain=",
            "nsosstatuserrordomain",
            "foundation.",
            "backend",
        ]

        return technicalMarkers.contains { normalized.contains($0) }
    }

    private nonisolated static func looksLikeTransportIssue(_ normalized: String) -> Bool {
        let transportMarkers = [
            "network connection was lost",
            "not connected to the internet",
            "socket is not connected",
            "cannot connect to host",
            "cannot find host",
            "dns lookup failed",
            "timed out",
            "connection aborted",
            "websocket",
        ]

        return transportMarkers.contains { normalized.contains($0) }
    }
}
