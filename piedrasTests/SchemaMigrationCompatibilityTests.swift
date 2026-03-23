import Foundation
import SwiftData
import Testing
@testable import piedras

private enum LegacySchemaMigrationModels {
    @Model
    final class Meeting {
        @Attribute(.unique) var id: String
        var title: String
        var date: Date
        var statusRaw: String
        var recordingModeRaw: String
        var durationSeconds: Int
        var userNotesPlainText: String
        var enhancedNotes: String
        var audioLocalPath: String?
        var audioRemotePath: String?
        var audioMimeType: String?
        var audioDuration: Int
        var audioUpdatedAt: Date?
        var sourceAudioLocalPath: String?
        var sourceAudioDisplayName: String?
        var sourceAudioDuration: Int
        var hiddenWorkspaceId: String?
        var syncStateRaw: String
        var lastSyncedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString.lowercased(),
            title: String = "",
            date: Date = .now,
            statusRaw: String = MeetingStatus.idle.rawValue,
            recordingModeRaw: String = MeetingRecordingMode.microphone.rawValue,
            durationSeconds: Int = 0,
            userNotesPlainText: String = "",
            enhancedNotes: String = "",
            audioLocalPath: String? = nil,
            audioRemotePath: String? = nil,
            audioMimeType: String? = nil,
            audioDuration: Int = 0,
            audioUpdatedAt: Date? = nil,
            sourceAudioLocalPath: String? = nil,
            sourceAudioDisplayName: String? = nil,
            sourceAudioDuration: Int = 0,
            hiddenWorkspaceId: String? = nil,
            syncStateRaw: String = MeetingSyncState.pending.rawValue,
            lastSyncedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.date = date
            self.statusRaw = statusRaw
            self.recordingModeRaw = recordingModeRaw
            self.durationSeconds = durationSeconds
            self.userNotesPlainText = userNotesPlainText
            self.enhancedNotes = enhancedNotes
            self.audioLocalPath = audioLocalPath
            self.audioRemotePath = audioRemotePath
            self.audioMimeType = audioMimeType
            self.audioDuration = audioDuration
            self.audioUpdatedAt = audioUpdatedAt
            self.sourceAudioLocalPath = sourceAudioLocalPath
            self.sourceAudioDisplayName = sourceAudioDisplayName
            self.sourceAudioDuration = sourceAudioDuration
            self.hiddenWorkspaceId = hiddenWorkspaceId
            self.syncStateRaw = syncStateRaw
            self.lastSyncedAt = lastSyncedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class SegmentAnnotation {
        @Attribute(.unique) var id: String
        var comment: String
        var imageFileNames: [String]
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString.lowercased(),
            comment: String = "",
            imageFileNames: [String] = [],
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.comment = comment
            self.imageFileNames = imageFileNames
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

struct SchemaMigrationCompatibilityTests {
    @MainActor
    @Test
    func currentSchemaOpensStoreCreatedWithoutImageTextFields() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
        }

        let legacySchema = Schema([
            LegacySchemaMigrationModels.Meeting.self,
            LegacySchemaMigrationModels.SegmentAnnotation.self,
        ])
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: [legacyConfiguration])

        let legacyMeeting = LegacySchemaMigrationModels.Meeting(title: "旧会议")
        let legacyAnnotation = LegacySchemaMigrationModels.SegmentAnnotation(comment: "旧评论")
        legacyContainer.mainContext.insert(legacyMeeting)
        legacyContainer.mainContext.insert(legacyAnnotation)
        try legacyContainer.mainContext.save()

        let currentSchema = Schema([
            Meeting.self,
            TranscriptSegment.self,
            ChatMessage.self,
            ChatSession.self,
            SegmentAnnotation.self,
        ])
        let currentConfiguration = ModelConfiguration(schema: currentSchema, url: storeURL)

        let currentContainer = try #require(
            try? ModelContainer(for: currentSchema, configurations: [currentConfiguration])
        )

        let meetings = try currentContainer.mainContext.fetch(FetchDescriptor<Meeting>())
        let annotations = try currentContainer.mainContext.fetch(FetchDescriptor<SegmentAnnotation>())

        #expect(meetings.count == 1)
        #expect(meetings.first?.title == "旧会议")
        #expect(meetings.first?.hasPendingImageTextRefresh == false)

        #expect(annotations.count == 1)
        #expect(annotations.first?.comment == "旧评论")
        #expect(annotations.first?.imageTextContext == "")
        #expect(annotations.first?.imageTextStatus == .idle)
    }
}
