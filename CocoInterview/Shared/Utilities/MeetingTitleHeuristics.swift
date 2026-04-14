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

    private static let lowSignalGeneratedTitles: Set<String> = [
        "测试",
        "语音测试",
        "录音测试",
        "会议测试",
        "今天",
        "现在",
        "日期确认",
        "时间确认",
        "效果如何",
        "看看效果",
    ]

    private static let lowSignalCandidateTitles: Set<String> = [
        "测试",
        "会议测试",
        "今天",
        "现在",
        "日期确认",
        "时间确认",
        "效果如何",
        "看看效果",
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
        let sentences = cleanedTranscript(from: transcript)
            .split(whereSeparator: { character in
                "。！？!?；;\n".contains(character)
            })
            .map { normalizedTitleSentence(from: String($0)) }
            .filter { !isLowSignalTitle($0) }

        let candidates = Array(sentences.prefix(5))

        if candidates.count >= 2,
           candidates[0].contains("测试"),
           candidates[1].contains("验证") {
            return sanitizedTitle(from: "\(candidates[0])与\(candidates[1])")
        }

        if let first = candidates.first, first.count >= minTitleLength {
            return sanitizedTitle(from: first)
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

    private static func cleanedTranscript(from transcript: String) -> String {
        transcript
            .replacingOccurrences(of: "\\[[^\\]]+\\]\\s*:?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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

    private static func normalizedTitleSentence(from sentence: String) -> String {
        let compact = sentence
            .replacingOccurrences(of: "[，。！？、,.!?:：；;（）()“”\"'‘’·\\-\\[\\]]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "今天是?\\d{2,4}年\\d{1,2}月\\d{1,2}日", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\d{2,4}年\\d{1,2}月\\d{1,2}日", with: "", options: .regularExpression)
            .replacingOccurrences(of: "现在进行", with: "")
            .replacingOccurrences(of: "进行语音测试", with: "语音测试")
            .replacingOccurrences(of: "看一下这个转写的效果如何", with: "转写效果验证")
            .replacingOccurrences(of: "看一下这个转息的效果如何", with: "转写效果验证")
            .replacingOccurrences(of: "看一下转写的效果如何", with: "转写效果验证")
            .replacingOccurrences(of: "看一下转息的效果如何", with: "转写效果验证")
            .replacingOccurrences(of: "看一下效果如何", with: "效果验证")
            .replacingOccurrences(of: "转写的效果如何", with: "转写效果验证")
            .replacingOccurrences(of: "转息的效果如何", with: "转写效果验证")
            .replacingOccurrences(of: "这个转写效果验证", with: "转写效果验证")
            .replacingOccurrences(of: "这个转息效果验证", with: "转写效果验证")
            .replacingOccurrences(of: "效果如何", with: "效果验证")

        return strippedTrailingPhrases(from: strippedLeadingPhrases(from: compact))
    }

    private static func isLowSignalTitle(_ title: String) -> Bool {
        if title.count < minTitleLength {
            return true
        }

        if lowSignalCandidateTitles.contains(title) {
            return true
        }

        if title.range(of: "\\d{2,4}年\\d{1,2}月\\d{1,2}日", options: .regularExpression) != nil {
            return true
        }

        if title.hasPrefix("今天") || title.hasPrefix("现在") || title.hasPrefix("这是") {
            return true
        }

        if title.contains("进行测试") || title.contains("看一下") || title.contains("效果如何") {
            return true
        }

        return false
    }

    static func shouldRejectGeneratedTitle(_ title: String) -> Bool {
        let sanitized = sanitizedTitle(from: title)
        if sanitized.isEmpty {
            return true
        }

        if lowSignalGeneratedTitles.contains(sanitized) {
            return true
        }

        return isLowSignalTitle(sanitized) || sanitized.contains("会议于")
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
