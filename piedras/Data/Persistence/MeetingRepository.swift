import Foundation
import SwiftData

@MainActor
final class MeetingRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchMeetings(matching query: String = "") throws -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\Meeting.updatedAt, order: .reverse)]
        )
        let meetings = try modelContext.fetch(descriptor)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedQuery.isEmpty else {
            return meetings
        }

        return meetings.filter { $0.searchIndexText.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    func meeting(withID id: String) throws -> Meeting? {
        let predicate = #Predicate<Meeting> { meeting in
            meeting.id == id
        }
        let descriptor = FetchDescriptor<Meeting>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func createDraftMeeting(hiddenWorkspaceID: String?) throws -> Meeting {
        let meeting = Meeting(
            status: .idle,
            hiddenWorkspaceId: hiddenWorkspaceID,
            syncState: .pending
        )
        modelContext.insert(meeting)
        try save()
        return meeting
    }

    func save() throws {
        try modelContext.save()
    }

    func delete(_ meeting: Meeting) throws {
        modelContext.delete(meeting)
        try save()
    }

    func seedPreviewDataIfNeeded(workspaceID: String?) {
        let existing: [Meeting]
        do {
            existing = try fetchMeetings()
        } catch {
            return
        }

        guard existing.isEmpty else {
            return
        }

        let planning = Meeting(
            title: "Piedras iOS MVP Kickoff",
            date: .now.addingTimeInterval(-7_200),
            status: .ended,
            durationSeconds: 1_542,
            userNotesPlainText: "核心范围：录音、转写、笔记、AI 总结。",
            enhancedNotes: "总结：先做一个极简可上线版本，复杂工作流全部后置。",
            hiddenWorkspaceId: workspaceID,
            syncState: .synced,
            lastSyncedAt: .now.addingTimeInterval(-3_600),
            createdAt: .now.addingTimeInterval(-7_200),
            updatedAt: .now.addingTimeInterval(-2_400)
        )

        planning.segments = [
            TranscriptSegment(
                speaker: "Speaker A",
                text: "我们先把 iOS 版本做成一个轻量录音笔记工具。",
                startTime: 0,
                endTime: 5_200,
                orderIndex: 0
            ),
            TranscriptSegment(
                speaker: "Speaker B",
                text: "工作区、知识库、导出这些先全部砍掉。",
                startTime: 5_400,
                endTime: 9_700,
                orderIndex: 1
            ),
        ]

        let review = Meeting(
            title: "会议记录体验回顾",
            date: .now.addingTimeInterval(-86_400),
            status: .ended,
            durationSeconds: 882,
            userNotesPlainText: "需要更快打开录音，详情页结构要简单。",
            enhancedNotes: "",
            hiddenWorkspaceId: workspaceID,
            syncState: .failed,
            createdAt: .now.addingTimeInterval(-86_400),
            updatedAt: .now.addingTimeInterval(-76_000)
        )

        review.chatMessages = [
            ChatMessage(role: "user", content: "帮我总结用户最关心的问题", orderIndex: 0),
            ChatMessage(role: "assistant", content: "核心问题是打开速度、录音稳定性和笔记编辑简洁度。", orderIndex: 1),
        ]

        modelContext.insert(planning)
        modelContext.insert(review)

        try? save()
    }
}
