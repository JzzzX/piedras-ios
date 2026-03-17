import Foundation
import Observation

@MainActor
@Observable
final class MeetingStore {
    private let repository: MeetingRepository
    private let settingsStore: SettingsStore
    private let recordingSessionStore: RecordingSessionStore
    private let audioRecorderService: AudioRecorderService

    var meetings: [Meeting] = []
    var selectedMeetingID: String?
    var searchText = "" {
        didSet {
            loadMeetings()
        }
    }
    var isLoading = false
    var lastErrorMessage: String?
    private var didLoad = false

    init(
        repository: MeetingRepository,
        settingsStore: SettingsStore,
        recordingSessionStore: RecordingSessionStore,
        audioRecorderService: AudioRecorderService
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.recordingSessionStore = recordingSessionStore
        self.audioRecorderService = audioRecorderService

        self.audioRecorderService.onProgress = { [weak self] level, duration in
            self?.handleRecordingProgress(level: level, duration: duration)
        }
    }

    var selectedMeeting: Meeting? {
        guard let selectedMeetingID else { return nil }
        return try? repository.meeting(withID: selectedMeetingID)
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        loadMeetings()
    }

    func loadMeetings() {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try repository.fetchMeetings(matching: searchText)
            if let selectedMeetingID,
               meetings.contains(where: { $0.id == selectedMeetingID }) {
                return
            }
            selectedMeetingID = meetings.first?.id
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createMeeting() -> Meeting? {
        do {
            let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: settingsStore.hiddenWorkspaceID)
            loadMeetings()
            selectedMeetingID = meeting.id
            return meeting
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func selectMeeting(id: String) {
        selectedMeetingID = id
    }

    func meeting(withID id: String) -> Meeting? {
        try? repository.meeting(withID: id)
    }

    func updateTitle(_ title: String, for meeting: Meeting) {
        meeting.title = title
        meeting.markPending()
        persistChanges()
    }

    func updateNotes(_ notes: String, for meeting: Meeting) {
        meeting.userNotesPlainText = notes
        meeting.markPending()
        persistChanges()
    }

    func persistChanges() {
        do {
            try repository.save()
            loadMeetings()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteMeeting(id: String) {
        guard let meeting = meeting(withID: id) else { return }

        do {
            try repository.delete(meeting)
            if selectedMeetingID == id {
                selectedMeetingID = nil
            }
            if recordingSessionStore.meetingID == id {
                recordingSessionStore.reset()
            }
            loadMeetings()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func startRecording(meetingID: String) async {
        if let activeMeetingID = recordingSessionStore.meetingID,
           activeMeetingID != meetingID,
           recordingSessionStore.phase != .idle {
            recordingSessionStore.errorBanner = "请先结束当前录音，再开始新的会议。"
            return
        }

        guard let meeting = meeting(withID: meetingID) else { return }

        do {
            recordingSessionStore.errorBanner = nil
            recordingSessionStore.meetingID = meetingID
            recordingSessionStore.phase = .starting
            let fileURL = try await audioRecorderService.startRecording(meetingID: meetingID)
            recordingSessionStore.phase = .recording
            meeting.date = .now
            meeting.audioLocalPath = fileURL.path
            meeting.audioMimeType = "audio/m4a"
            meeting.audioUpdatedAt = .now
            meeting.status = .recording
            meeting.markPending()
            try repository.save()
            selectedMeetingID = meetingID
            loadMeetings()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
            recordingSessionStore.phase = .idle
            recordingSessionStore.meetingID = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func pauseRecording() {
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            try audioRecorderService.pauseRecording()
            recordingSessionStore.phase = .paused
            meeting.status = .paused
            meeting.markPending()
            try repository.save()
            loadMeetings()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func resumeRecording() {
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            try audioRecorderService.resumeRecording()
            recordingSessionStore.phase = .recording
            meeting.status = .recording
            meeting.markPending()
            try repository.save()
            loadMeetings()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            let artifact = try audioRecorderService.stopRecording()
            meeting.status = .ended
            meeting.audioLocalPath = artifact.fileURL.path
            meeting.audioMimeType = artifact.mimeType
            meeting.audioDuration = artifact.durationSeconds
            meeting.audioUpdatedAt = .now
            meeting.durationSeconds = max(meeting.durationSeconds, artifact.durationSeconds)
            meeting.markPending()
            try repository.save()
            recordingSessionStore.reset()
            loadMeetings()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    private func currentRecordingMeeting() -> Meeting? {
        guard let meetingID = recordingSessionStore.meetingID else { return nil }
        return meeting(withID: meetingID)
    }

    private func handleRecordingProgress(level: Double, duration: Int) {
        recordingSessionStore.pushAudioLevelSample(level)
        recordingSessionStore.durationSeconds = duration

        guard let meeting = currentRecordingMeeting() else { return }
        guard meeting.durationSeconds != duration else { return }

        meeting.durationSeconds = duration
        meeting.audioDuration = duration
        meeting.updatedAt = .now
        try? repository.save()
    }
}
