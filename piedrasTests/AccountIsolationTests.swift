import Foundation
import Testing
@testable import piedras

@Suite(.serialized)
struct AccountIsolationTests {
    @MainActor
    @Test
    func logoutBlockingMessageAppearsWhenPendingMeetingsExist() throws {
        let appContainer = try makeAppContainer()
        try resetLocalState(in: appContainer)

        appContainer.settingsStore.hiddenWorkspaceID = "workspace-1"
        _ = try appContainer.meetingRepository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        appContainer.meetingStore.loadMeetings()

        let message = appContainer.meetingStore.logoutBlockingMessage()

        #expect(message?.contains("未同步") == true)
    }

    @MainActor
    @Test
    func resetLocalAccountDataPurgesMeetingsAndGlobalChats() throws {
        let appContainer = try makeAppContainer()
        try resetLocalState(in: appContainer)

        appContainer.settingsStore.hiddenWorkspaceID = "workspace-1"
        _ = try appContainer.meetingRepository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        let globalSession = appContainer.chatSessionRepository.makeDraftSession(scope: .global, meeting: nil)
        appContainer.chatSessionRepository.appendUserMessage("hello", to: globalSession)
        try appContainer.chatSessionRepository.save()
        appContainer.meetingStore.loadMeetings()

        appContainer.meetingStore.resetLocalAccountData()

        #expect(try appContainer.meetingRepository.fetchMeetings(includeDeleted: true).isEmpty)
        #expect(try appContainer.chatSessionRepository.fetchSessions(scope: .global).isEmpty)
        #expect(appContainer.settingsStore.hiddenWorkspaceID == nil)
        #expect(appContainer.meetingStore.meetings.isEmpty)
    }

    @MainActor
    private func makeAppContainer() throws -> AppContainer {
        if let container = AppContainer.currentXCTestInstance {
            return container
        }

        return AppContainer(inMemory: true)
    }

    @MainActor
    private func resetLocalState(in appContainer: AppContainer) throws {
        let repository = appContainer.meetingRepository
        let meetings = try repository.fetchMeetings(includeDeleted: true)
        for meeting in meetings {
            try repository.delete(meeting)
        }

        let globalSessions = try appContainer.chatSessionRepository.fetchSessions(scope: .global)
        for session in globalSessions {
            try appContainer.chatSessionRepository.delete(session)
        }

        appContainer.settingsStore.hiddenWorkspaceID = nil
        appContainer.meetingStore.loadMeetings()
    }
}
