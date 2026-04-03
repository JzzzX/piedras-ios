import Foundation
import SwiftData

@MainActor
final class MeetingRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchMeetings(
        matching query: String = "",
        collectionID: String? = nil,
        includeDeleted: Bool = false
    ) throws -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\Meeting.updatedAt, order: .reverse)]
        )
        let meetings = try modelContext.fetch(descriptor)
            .filter { includeDeleted || $0.syncState != .deleted }
            .filter { collectionID == nil || $0.collectionId == collectionID }
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
    func createDraftMeeting(hiddenWorkspaceID: String?, collectionID: String? = nil) throws -> Meeting {
        let meeting = Meeting(
            status: .idle,
            hiddenWorkspaceId: hiddenWorkspaceID,
            collectionId: collectionID,
            syncState: .pending
        )
        modelContext.insert(meeting)
        try save()
        return meeting
    }

    func save() throws {
        try modelContext.save()
    }

    func insert(_ meeting: Meeting) {
        modelContext.insert(meeting)
    }

    func delete(_ meeting: Meeting) throws {
        modelContext.delete(meeting)
        try save()
    }

    func deleteAllMeetings() throws {
        let meetings = try fetchMeetings(includeDeleted: true)
        for meeting in meetings {
            modelContext.delete(meeting)
        }
        try save()
    }

    func delete(_ chatMessage: ChatMessage) {
        modelContext.delete(chatMessage)
    }

    func replaceSegments(for meeting: Meeting, with segments: [TranscriptSegment]) {
        let existingByID = Dictionary(uniqueKeysWithValues: meeting.segments.map { ($0.id, $0) })
        let incomingIDs = Set(segments.map(\.id))

        let mergedSegments = segments.map { incomingSegment -> TranscriptSegment in
            guard let existingSegment = existingByID[incomingSegment.id] else {
                incomingSegment.meeting = meeting
                return incomingSegment
            }

            existingSegment.speaker = incomingSegment.speaker
            existingSegment.text = incomingSegment.text
            existingSegment.startTime = incomingSegment.startTime
            existingSegment.endTime = incomingSegment.endTime
            existingSegment.isFinal = incomingSegment.isFinal
            existingSegment.orderIndex = incomingSegment.orderIndex
            existingSegment.confidence = incomingSegment.confidence
            existingSegment.meeting = meeting
            return existingSegment
        }

        for existingSegment in meeting.segments where !incomingIDs.contains(existingSegment.id) {
            modelContext.delete(existingSegment)
        }

        meeting.segments = mergedSegments
    }

    func replaceChatMessages(for meeting: Meeting, with chatMessages: [ChatMessage]) {
        for existingMessage in meeting.chatMessages {
            modelContext.delete(existingMessage)
        }

        for message in chatMessages {
            message.meeting = meeting
        }

        meeting.chatMessages = chatMessages
    }

    func replaceChatMessages(for meeting: Meeting, in session: ChatSession, with chatMessages: [ChatMessage]) {
        for existingMessage in meeting.chatMessages {
            modelContext.delete(existingMessage)
        }

        session.messages.removeAll(keepingCapacity: true)

        for message in chatMessages {
            message.meeting = meeting
            message.session = session
        }

        meeting.chatMessages = chatMessages
        session.messages = chatMessages
    }

    func mergeChatMessages(for meeting: Meeting, with chatMessages: [ChatMessage]) {
        let existingByID = Dictionary(uniqueKeysWithValues: meeting.chatMessages.map { ($0.id, $0) })
        var mergedMessages = meeting.chatMessages

        for incomingMessage in chatMessages {
            if let existingMessage = existingByID[incomingMessage.id] {
                existingMessage.role = incomingMessage.role
                existingMessage.content = incomingMessage.content
                existingMessage.timestamp = incomingMessage.timestamp
                continue
            }

            incomingMessage.meeting = meeting
            mergedMessages.append(incomingMessage)
        }

        mergedMessages.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }

        for (index, message) in mergedMessages.enumerated() {
            message.orderIndex = index
            message.meeting = meeting
        }

        meeting.chatMessages = mergedMessages
    }

    func mergeChatMessages(for meeting: Meeting, in session: ChatSession, with chatMessages: [ChatMessage]) {
        mergeChatMessages(for: meeting, with: chatMessages)
        let orderedMessages = meeting.orderedChatMessages
        for message in orderedMessages {
            message.session = session
        }
        session.messages = orderedMessages
    }

    func seedPreviewDataIfNeeded(workspaceID: String?, preferLocalOnly: Bool = false) {
        let existing: [Meeting]
        do {
            existing = try fetchMeetings(includeDeleted: true)
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
            enhancedNotes: """
            ## 会议摘要
            先做一个极简可上线的 iOS 录音笔记版本，复杂工作流全部后置。

            ## 关键讨论点
            - 聚焦录音、转写、笔记与 AI 总结
            - 工作区、知识库和导出能力暂不进入 MVP

            ## 决策事项
            - 当前阶段优先做单会议闭环

            ## 行动项
            - [ ] 完成 ASR 真实联调
            - [ ] 收紧详情页信息层级
            """,
            hiddenWorkspaceId: workspaceID,
            collectionId: "preview-notes",
            syncState: preferLocalOnly ? .pending : .synced,
            lastSyncedAt: preferLocalOnly ? nil : .now.addingTimeInterval(-3_600),
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
            collectionId: "preview-notes",
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
