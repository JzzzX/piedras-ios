import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text("AI")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer()

                AppGlassCapsuleButton(
                    prominent: canGenerate,
                    minHeight: 38,
                    fillsWidth: false,
                    action: {
                        Task {
                            await meetingStore.generateEnhancedNotes(for: meeting.id)
                        }
                    }
                ) {
                    HStack(spacing: 7) {
                        Image(systemName: meetingStore.isEnhancing(meetingID: meeting.id) ? "hourglass" : "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text(actionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(canGenerate && !isLLMUnavailable ? .white : AppTheme.subtleInk)
                    .padding(.horizontal, 12)
                }
                .disabled(meetingStore.isEnhancing(meetingID: meeting.id) || !canGenerate || isLLMUnavailable)
            }

            Group {
                if meetingStore.isEnhancing(meetingID: meeting.id) && meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("Generating...")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.subtleInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let blockingMessage, meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(blockingMessage)
                        .font(.body)
                        .foregroundStyle(AppTheme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Generate a note.")
                        .font(.body)
                        .foregroundStyle(AppTheme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let markdown = try? AttributedString(markdown: meeting.enhancedNotes) {
                    Text(markdown)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(meeting.enhancedNotes)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var canGenerate: Bool {
        !meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLLMUnavailable: Bool {
        settingsStore.blockingMessage(for: .ai) != nil
    }

    private var blockingMessage: String? {
        settingsStore.blockingMessage(for: .ai)
    }

    private var actionTitle: String {
        if meetingStore.isEnhancing(meetingID: meeting.id) {
            return "Working"
        }

        return meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generate" : "Refresh"
    }
}
