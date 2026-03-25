import Foundation

enum UserVisibleMediaErrorFormatter {
    nonisolated static func transcriptionFailureDetail(from rawMessage: String?) -> String? {
        friendlyMessage(
            from: rawMessage,
            technicalFallback: nil,
            genericAudioFallback: currentStrings.audioFileNeedsReexport
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
}
