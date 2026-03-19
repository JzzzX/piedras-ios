import Foundation

enum MeetingTitleHeuristics {
    private static let shortMemoThresholdSeconds = 45
    private static let minTitleLength = 4
    private static let maxTitleLength = 18
    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let leadingPhrases = [
        "我们今天主要讨论一下",
        "我们今天主要聊一下",
        "今天主要讨论一下",
        "今天主要聊一下",
        "我们今天讨论一下",
        "我们今天聊一下",
        "今天讨论一下",
        "今天聊一下",
        "我们来聊聊",
        "我想聊聊",
        "我们先看一下",
        "我们先聊一下",
        "我们先聊聊",
        "我们先把",
        "先看一下",
        "先聊一下",
        "先聊聊",
        "先把",
        "主要是关于",
        "就是关于",
        "关于",
        "主要聊",
        "讨论",
        "聊一下",
        "聊聊",
        "说一下",
        "想说",
        "就是说",
        "就是",
        "那个",
        "这个",
        "嗯",
        "啊",
    ]

    private static let trailingPhrases = [
        "的安排",
        "这个安排",
        "这件事情",
        "这个事情",
        "这个问题",
        "的问题",
        "一下",
    ]

    static func fallbackTitle(
        transcript: String,
        finalSegmentCount: Int,
        durationSeconds: Int,
        meetingDate: Date
    ) -> String {
        if let keyPhrase = keyPhraseTitle(from: transcript) {
            return keyPhrase
        }

        if durationSeconds > 0, durationSeconds <= shortMemoThresholdSeconds {
            return "语音备忘 \(durationSeconds.mmss)"
        }

        if isLowInformation(transcript: transcript, finalSegmentCount: finalSegmentCount) {
            return recordingTitle(for: meetingDate)
        }

        return recordingTitle(for: meetingDate)
    }

    static func sanitizedTitle(from rawTitle: String) -> String {
        let compact = rawTitle
            .replacingOccurrences(of: "[\\n\\r#>*`]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else {
            return ""
        }

        return String(compact.prefix(maxTitleLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func keyPhraseTitle(from transcript: String) -> String? {
        let cleanedTranscript = transcript
            .replacingOccurrences(of: "\\[[^\\]]+\\]\\s*:?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let sentences = cleanedTranscript
            .split(whereSeparator: { character in
                "。！？!?；;\n".contains(character)
            })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for sentence in sentences.prefix(3) {
            let candidate = cleanedTitleCandidate(from: sentence)
            if candidate.count >= minTitleLength {
                return candidate
            }
        }

        return nil
    }

    static func isLowInformation(transcript: String, finalSegmentCount: Int) -> Bool {
        if finalSegmentCount < 2 {
            return true
        }

        let compact = transcript
            .replacingOccurrences(of: "\\[[^\\]]+\\]\\s*:?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        return compact.count < 12
    }

    static func recordingTitle(for date: Date) -> String {
        "\(fallbackDateFormatter.string(from: date)) 录音"
    }

    private static func cleanedTitleCandidate(from sentence: String) -> String {
        let compact = sentence
            .replacingOccurrences(of: "[，。！？、,.!?:：；;（）()“”\"'‘’·\\-\\[\\]]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        let stripped = strippedTrailingPhrases(from: strippedLeadingPhrases(from: compact))
        let trimmed = sanitizedTitle(from: stripped)

        if trimmed.count > maxTitleLength {
            return String(trimmed.prefix(maxTitleLength))
        }

        return trimmed
    }

    private static func strippedLeadingPhrases(from source: String) -> String {
        var value = source
        var didStrip = true

        while didStrip {
            didStrip = false

            for phrase in leadingPhrases where value.hasPrefix(phrase) {
                value = String(value.dropFirst(phrase.count))
                didStrip = true
            }
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strippedTrailingPhrases(from source: String) -> String {
        var value = source
        var didStrip = true

        while didStrip {
            didStrip = false

            for phrase in trailingPhrases where value.hasSuffix(phrase) {
                value = String(value.dropLast(phrase.count))
                didStrip = true
            }
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
