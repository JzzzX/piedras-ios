import Foundation

enum ChatSessionHistoryBucket: CaseIterable {
    case today
    case yesterday
    case earlierThisWeek
    case earlier

    var title: String {
        switch self {
        case .today: return AppStrings.current.bucketToday
        case .yesterday: return AppStrings.current.bucketYesterday
        case .earlierThisWeek: return AppStrings.current.bucketEarlierThisWeek
        case .earlier: return AppStrings.current.bucketEarlier
        }
    }
}

struct ChatSessionHistorySection: Identifiable {
    let bucket: ChatSessionHistoryBucket
    let sessions: [ChatSession]

    var id: String { bucket.title }

    static func makeSections(
        from sessions: [ChatSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ChatSessionHistorySection] {
        var grouped: [ChatSessionHistoryBucket: [ChatSession]] = [:]

        for session in sessions {
            let bucket = bucket(for: session.updatedAt, now: now, calendar: calendar)
            grouped[bucket, default: []].append(session)
        }

        return ChatSessionHistoryBucket.allCases.compactMap { bucket in
            guard let bucketSessions = grouped[bucket], !bucketSessions.isEmpty else { return nil }
            return ChatSessionHistorySection(
                bucket: bucket,
                sessions: bucketSessions.sorted { lhs, rhs in
                    if lhs.updatedAt == rhs.updatedAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.updatedAt > rhs.updatedAt
                }
            )
        }
    }

    private static func bucket(for date: Date, now: Date, calendar: Calendar) -> ChatSessionHistoryBucket {
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }

        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
           weekInterval.contains(date) {
            return .earlierThisWeek
        }

        return .earlier
    }
}

extension ChatSession {
    func historyMetadataLine(referenceDate: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(updatedAt, inSameDayAs: referenceDate)
            || calendar.isDateInYesterday(updatedAt) {
            return updatedAt.formatted(.dateTime.hour().minute())
        }

        return updatedAt.formatted(.dateTime.month(.wide).day())
    }
}
