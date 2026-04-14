import Foundation

enum MeetingSearchSource: String, CaseIterable, Hashable, Codable {
    case transcript
    case userNotes
    case enhancedNotes
    case comment
    case imageText

    var label: String {
        switch self {
        case .transcript:
            return AppStrings.current.transcript
        case .userNotes:
            return AppStrings.current.userNotesSource
        case .enhancedNotes:
            return AppStrings.current.aiNotes
        case .comment:
            return AppStrings.current.commentSource
        case .imageText:
            return AppStrings.current.imageTextSource
        }
    }
}

struct MeetingSearchResult: Identifiable, Hashable {
    let meeting: Meeting
    let matchedSources: [MeetingSearchSource]

    var id: String { meeting.id }

    static func == (lhs: MeetingSearchResult, rhs: MeetingSearchResult) -> Bool {
        lhs.id == rhs.id && lhs.matchedSources == rhs.matchedSources
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(matchedSources)
    }
}

struct LocalMeetingRetrievalSource: Encodable, Hashable {
    let ref: String
    let type: String
    let title: String
    let date: String
}

struct LocalMeetingRetrievalResult: Hashable {
    let sources: [LocalMeetingRetrievalSource]
    let context: String
}

enum MeetingSearchIndexBuilder {
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

    static func searchIndexText(for meeting: Meeting) -> String {
        let sections = searchableSections(for: meeting)
            .map(\.text)
            .filter { !$0.isEmpty }

        return ([meeting.title] + sections)
            .joined(separator: "\n")
            .lowercased()
    }

    static func matchedSources(for meeting: Meeting, query: String) -> [MeetingSearchSource] {
        let tokens = queryTokens(from: query)
        guard !tokens.isEmpty else { return [] }

        var matches: [MeetingSearchSource] = []
        for section in searchableSections(for: meeting) {
            guard tokens.contains(where: { section.text.localizedCaseInsensitiveContains($0) }) else {
                continue
            }
            if !matches.contains(section.source) {
                matches.append(section.source)
            }
        }

        return matches
    }

    static func searchResults(for meetings: [Meeting], query: String) -> [MeetingSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return meetings.map {
                MeetingSearchResult(meeting: $0, matchedSources: [])
            }
        }

        let tokens = queryTokens(from: trimmedQuery)

        return meetings
            .compactMap { meeting -> (result: MeetingSearchResult, score: Double)? in
                let matches = matchedSources(for: meeting, query: trimmedQuery)
                let titleMatches = titleMatchScore(for: meeting, query: trimmedQuery, tokens: tokens)
                guard titleMatches > 0 || !matches.isEmpty else {
                    return nil
                }

                return (
                    MeetingSearchResult(meeting: meeting, matchedSources: matches),
                    Double(matches.count) + titleMatches
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.result.meeting.updatedAt > rhs.result.meeting.updatedAt
                }
                return lhs.score > rhs.score
            }
            .map(\.result)
    }

    static func localRetrievalResult(
        for question: String,
        meetings: [Meeting],
        collectionID: String?
    ) -> LocalMeetingRetrievalResult {
        let keywords = queryTokens(from: question)
        let filteredMeetings = meetings.filter { collectionID == nil || $0.collectionId == collectionID }

        let ranked = filteredMeetings
            .map { meeting in
                RankedMeeting(
                    meeting: meeting,
                    score: score(meeting: meeting, keywords: keywords),
                    snippets: snippets(for: meeting, keywords: keywords)
                )
            }
            .filter { !$0.snippets.isEmpty || $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.meeting.updatedAt > $1.meeting.updatedAt
                }
                return $0.score > $1.score
            }

        let selected = Array((ranked.isEmpty ? [] : ranked.prefix(5)))
        let sources = selected.enumerated().map { index, item in
            LocalMeetingRetrievalSource(
                ref: "S\(index + 1)",
                type: "meeting",
                title: item.meeting.displayTitle,
                date: item.meeting.date.ISO8601Format()
            )
        }

        let context = selected.enumerated().map { index, item in
            let ref = "S\(index + 1)"
            let dateText = item.meeting.date.formatted(.dateTime.year().month().day().hour().minute())
            let snippetText = item.snippets.map { "- \($0)" }.joined(separator: "\n")
            return "[\(ref)] 会议：\(item.meeting.displayTitle)（\(dateText)）\n\(snippetText)"
        }
            .joined(separator: "\n\n")

        return LocalMeetingRetrievalResult(sources: sources, context: context)
    }

    private static func score(meeting: Meeting, keywords: [String]) -> Double {
        guard !keywords.isEmpty else {
            return meeting.updatedAt.timeIntervalSince1970
        }

        let titleText = meeting.displayTitle.lowercased()
        var total = 0.0

        for keyword in keywords {
            if titleText.contains(keyword) {
                total += 0.9
            }

            for section in searchableSections(for: meeting) {
                let weight: Double
                switch section.source {
                case .enhancedNotes:
                    weight = 0.6
                case .userNotes:
                    weight = 0.45
                case .comment, .imageText:
                    weight = 0.55
                case .transcript:
                    weight = 0.3
                }

                if section.text.lowercased().contains(keyword) {
                    total += weight
                }
            }
        }

        return total
    }

    private static func snippets(for meeting: Meeting, keywords: [String]) -> [String] {
        let sections = searchableSections(for: meeting)

        let matched = sections.filter { section in
            guard !keywords.isEmpty else { return true }
            return keywords.contains(where: { section.text.localizedCaseInsensitiveContains($0) })
        }

        let candidates = matched.isEmpty
            ? sections.sorted { snippetPriority(for: $0.source) > snippetPriority(for: $1.source) }
            : matched
        return Array(
            candidates
                .map(\.preview)
                .map { compact($0) }
                .filter { !$0.isEmpty }
                .orderedUnique()
                .prefix(3)
        )
    }

    private static func searchableSections(for meeting: Meeting) -> [SearchSection] {
        var sections: [SearchSection] = []

        let trimmedNotes = meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            sections.append(SearchSection(source: .userNotes, text: trimmedNotes, preview: trimmedNotes))
        }

        let trimmedEnhancedNotes = meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEnhancedNotes.isEmpty {
            sections.append(SearchSection(source: .enhancedNotes, text: trimmedEnhancedNotes, preview: trimmedEnhancedNotes))
        }

        for segment in meeting.orderedSegments {
            let transcriptText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcriptText.isEmpty {
                sections.append(SearchSection(source: .transcript, text: transcriptText, preview: transcriptText))
            }

            let commentText = segment.annotation?.comment.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !commentText.isEmpty {
                sections.append(
                    SearchSection(
                        source: .comment,
                        text: "\(transcriptText)\n\(commentText)",
                        preview: commentText
                    )
                )
            }

            let imageText = segment.annotation?.imageTextContext.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !imageText.isEmpty {
                sections.append(
                    SearchSection(
                        source: .imageText,
                        text: "\(transcriptText)\n\(imageText)",
                        preview: imageText
                    )
                )
            }
        }

        return sections
    }

    private static func queryTokens(from query: String) -> [String] {
        let lowercased = query.lowercased()
        let pattern = #"[a-z0-9]{2,}|[\u4e00-\u9fa5]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(lowercased.startIndex..., in: lowercased)
        let matches = regex.matches(in: lowercased, range: range)

        var tokens: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard let matchRange = Range(match.range, in: lowercased) else {
                continue
            }

            let token = String(lowercased[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.count >= 2, !stopWords.contains(token), !seen.contains(token) else {
                continue
            }

            seen.insert(token)
            tokens.append(token)
        }

        return tokens
    }

    private static func compact(_ text: String, limit: Int = 180) -> String {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "..."
    }

    private static func snippetPriority(for source: MeetingSearchSource) -> Int {
        switch source {
        case .enhancedNotes:
            return 5
        case .userNotes:
            return 4
        case .comment:
            return 3
        case .imageText:
            return 2
        case .transcript:
            return 1
        }
    }

    private static func titleMatchScore(for meeting: Meeting, query: String, tokens: [String]) -> Double {
        let title = meeting.displayTitle.lowercased()
        if title.contains(query.lowercased()) {
            return 1.5
        }

        let matchedTokens = tokens.filter { title.contains($0) }
        guard !matchedTokens.isEmpty else { return 0 }
        return Double(matchedTokens.count) * 0.6
    }
}

private struct SearchSection: Hashable {
    let source: MeetingSearchSource
    let text: String
    let preview: String
}

private struct RankedMeeting {
    let meeting: Meeting
    let score: Double
    let snippets: [String]
}

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
