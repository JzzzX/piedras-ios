import Foundation

enum MeetingCommentContextBuilder {
    private static let meetingHeader = "--- 转写片段评论 ---"
    private static let globalHeader = "--- 本地补充评论上下文 ---"
    private static let meetingCharacterLimit = 3_200
    private static let globalCharacterLimit = 4_200
    private static let maxGlobalMeetings = 3
    private static let maxCommentsPerMeeting = 4
    private static let stopWords: Set<String> = [
        "我们",
        "你们",
        "这个",
        "那个",
        "哪些",
        "什么",
        "一下",
        "关于",
        "请问",
        "帮我",
        "会议",
        "总结",
        "分析",
        "问题",
        "情况",
    ]

    static func segmentCommentsContext(for meeting: Meeting) -> String {
        let entries = commentEntries(for: meeting).map(\.formatted)
        return boundedSections(header: meetingHeader, sections: entries, limit: meetingCharacterLimit)
    }

    static func localCommentContext(
        for question: String,
        meetings: [Meeting],
        workspaceID: String?
    ) -> String {
        let keywords = splitKeywords(question)
        let candidates = meetings.compactMap { meeting -> GlobalMeetingContext? in
            guard workspaceID == nil || meeting.hiddenWorkspaceId == workspaceID else {
                return nil
            }

            let entries = commentEntries(for: meeting)
            guard !entries.isEmpty else {
                return nil
            }

            let scoredEntries = entries.enumerated().map { index, entry in
                let searchableText = [
                    meeting.displayTitle,
                    entry.originalText,
                    entry.commentText,
                    entry.imageText,
                ]
                    .joined(separator: "\n")
                    .lowercased()
                let keywordHits = keywords.reduce(into: 0) { total, keyword in
                    if searchableText.contains(keyword) {
                        total += 1
                    }
                }

                return ScoredCommentEntry(
                    entry: entry,
                    originalIndex: index,
                    keywordHits: keywordHits
                )
            }

            let totalKeywordHits = scoredEntries.reduce(into: 0) { total, item in
                total += item.keywordHits
            }

            let prioritizedEntries: [CommentEntry]
            if keywords.isEmpty {
                prioritizedEntries = entries
            } else {
                prioritizedEntries = scoredEntries
                    .sorted {
                        if $0.keywordHits == $1.keywordHits {
                            return $0.originalIndex < $1.originalIndex
                        }
                        return $0.keywordHits > $1.keywordHits
                    }
                    .map(\.entry)
            }

            return GlobalMeetingContext(
                meeting: meeting,
                totalKeywordHits: totalKeywordHits,
                entries: Array(prioritizedEntries.prefix(maxCommentsPerMeeting))
            )
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            let lhsHasHits = lhs.totalKeywordHits > 0
            let rhsHasHits = rhs.totalKeywordHits > 0

            if lhsHasHits != rhsHasHits {
                return lhsHasHits
            }

            if lhs.totalKeywordHits != rhs.totalKeywordHits {
                return lhs.totalKeywordHits > rhs.totalKeywordHits
            }

            if lhs.meeting.updatedAt != rhs.meeting.updatedAt {
                return lhs.meeting.updatedAt > rhs.meeting.updatedAt
            }

            return lhs.meeting.createdAt > rhs.meeting.createdAt
        }

        let sections = sortedCandidates
            .prefix(maxGlobalMeetings)
            .map { candidate in
                let body = candidate.entries.map(\.formatted).joined(separator: "\n\n")
                return """
                会议：\(candidate.meeting.displayTitle)
                \(body)
                """
            }

        return boundedSections(header: globalHeader, sections: sections, limit: globalCharacterLimit)
    }

    private static func commentEntries(for meeting: Meeting) -> [CommentEntry] {
        let baseTime = transcriptBaseTime(for: meeting)

        return meeting.orderedSegments.compactMap { segment in
            let originalText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let commentText = segment.annotation?.comment.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let imageText = segment.annotation?.imageTextContext.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !originalText.isEmpty, (!commentText.isEmpty || !imageText.isEmpty) else {
                return nil
            }

            let timestamp = timestampLabel(for: segment.startTime, baseTime: baseTime)
            return CommentEntry(
                timestamp: timestamp,
                originalText: originalText,
                commentText: commentText,
                imageText: imageText
            )
        }
    }

    private static func boundedSections(header: String, sections: [String], limit: Int) -> String {
        let trimmedSections = sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedSections.isEmpty else {
            return ""
        }

        var output = header

        for section in trimmedSections {
            let separator = output == header ? "\n\n" : "\n\n"
            let candidate = output + separator + section

            if candidate.count <= limit {
                output = candidate
                continue
            }

            let remaining = max(limit - output.count - separator.count, 0)
            guard remaining > 0 else {
                break
            }

            output += separator + String(section.prefix(remaining))
            break
        }

        return output
    }

    private static func splitKeywords(_ question: String) -> [String] {
        let lowercased = question.lowercased()
        let pattern = #"[a-z0-9]{2,}|[\u4e00-\u9fa5]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(lowercased.startIndex..., in: lowercased)
        let matches = regex.matches(in: lowercased, range: range)

        var seen = Set<String>()
        var keywords: [String] = []

        for match in matches {
            guard let matchRange = Range(match.range, in: lowercased) else {
                continue
            }

            let token = String(lowercased[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            for candidate in expandedKeywords(from: token) {
                guard candidate.count >= 2, !stopWords.contains(candidate), !seen.contains(candidate) else {
                    continue
                }

                seen.insert(candidate)
                keywords.append(candidate)
            }
        }

        return keywords
    }

    private static func expandedKeywords(from token: String) -> [String] {
        var candidates = [token]
        let scalars = Array(token)

        guard scalars.count >= 2, token.range(of: #"[一-龥]"#, options: .regularExpression) != nil else {
            return candidates
        }

        for length in 2 ... min(3, scalars.count) {
            guard scalars.count >= length else {
                continue
            }

            for start in 0 ... (scalars.count - length) {
                candidates.append(String(scalars[start ..< start + length]))
            }
        }

        return candidates
    }

    private static func transcriptBaseTime(for meeting: Meeting) -> Double {
        guard let firstSegment = meeting.orderedSegments.first else {
            return 0
        }

        if firstSegment.startTime > 86_400_000 {
            return min(firstSegment.startTime, meeting.date.timeIntervalSince1970 * 1000)
        }

        return 0
    }

    private static func timestampLabel(for startTime: Double, baseTime: Double) -> String {
        let normalizedSeconds = max(0, (startTime - baseTime) / 1000)
        return TimeInterval(normalizedSeconds).mmss
    }
}

private struct CommentEntry {
    let timestamp: String
    let originalText: String
    let commentText: String
    let imageText: String

    var formatted: String {
        var lines = ["[\(timestamp)] 原句：\(originalText)"]

        if !commentText.isEmpty {
            lines.append("评论：\(commentText)")
        }

        if !imageText.isEmpty {
            lines.append("图片文字：\(imageText)")
        }

        return lines.joined(separator: "\n")
    }
}

private struct ScoredCommentEntry {
    let entry: CommentEntry
    let originalIndex: Int
    let keywordHits: Int
}

private struct GlobalMeetingContext {
    let meeting: Meeting
    let totalKeywordHits: Int
    let entries: [CommentEntry]
}
