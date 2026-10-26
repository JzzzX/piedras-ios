import Foundation

struct TranscriptSpeakerIdentity: Equatable {
    let avatarToken: String
    let title: String
    let defaultTitle: String
    let paletteIndex: Int

    static func resolve(
        speakerKey: String,
        displayName: String?,
        strings: AppStringTable = AppStrings.current
    ) -> Self {
        let normalizedSpeakerKey = speakerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let zeroBasedIndex = zeroBasedIndex(for: normalizedSpeakerKey) {
            let defaultTitle = strings.speakerLabel(zeroBasedIndex + 1)
            return TranscriptSpeakerIdentity(
                avatarToken: token(forIndex: zeroBasedIndex),
                title: normalizedDisplayName.isEmpty ? defaultTitle : normalizedDisplayName,
                defaultTitle: defaultTitle,
                paletteIndex: zeroBasedIndex
            )
        }

        let fallbackTitle = normalizedSpeakerKey.isEmpty ? strings.speakerLabel(1) : normalizedSpeakerKey
        return TranscriptSpeakerIdentity(
            avatarToken: fallbackToken(for: normalizedSpeakerKey),
            title: normalizedDisplayName.isEmpty ? fallbackTitle : normalizedDisplayName,
            defaultTitle: fallbackTitle,
            paletteIndex: stablePaletteIndex(for: normalizedSpeakerKey)
        )
    }

    static func token(forIndex zeroBasedIndex: Int) -> String {
        var value = max(0, zeroBasedIndex)
        var token = ""

        repeat {
            let remainder = value % 26
            let scalar = UnicodeScalar(65 + remainder)!
            token = String(Character(scalar)) + token
            value = (value / 26) - 1
        } while value >= 0

        return token
    }

    private static func zeroBasedIndex(for speakerKey: String) -> Int? {
        guard !speakerKey.isEmpty else { return 0 }

        if speakerKey.hasPrefix("spk_"),
           let index = Int(speakerKey.dropFirst(4)),
           index > 0 {
            return index - 1
        }

        let lowercased = speakerKey.lowercased()
        let localizedPrefixes = ["speaker ", "说话人 ", "发言人 "]

        for prefix in localizedPrefixes where lowercased.hasPrefix(prefix) {
            let suffix = speakerKey.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if let numeric = Int(suffix), numeric > 0 {
                return numeric - 1
            }

            if let alpha = alphaIndex(for: suffix) {
                return alpha
            }
        }

        return nil
    }

    private static func alphaIndex(for token: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }

        var total = 0
        for scalar in trimmed.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            total = (total * 26) + Int(scalar.value - 64)
        }

        return total - 1
    }

    private static func fallbackToken(for speakerKey: String) -> String {
        for scalar in speakerKey.uppercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                return String(Character(scalar))
            }
        }

        return "?"
    }

    private static func stablePaletteIndex(for speakerKey: String) -> Int {
        let normalized = speakerKey.isEmpty ? "default-speaker" : speakerKey
        return normalized.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult * 33) + Int(scalar.value)
        }
    }
}
