import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Smart notes")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.ink)

                    Text("Generated from the transcript and your notes.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtleInk)
                }

                Spacer()

                Button(meetingStore.isEnhancing(meetingID: meeting.id) ? "Thinking..." : actionTitle) {
                    Task {
                        await meetingStore.generateEnhancedNotes(for: meeting.id)
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(canGenerate ? AppTheme.ink : AppTheme.subtleInk, in: Capsule())
                .disabled(meetingStore.isEnhancing(meetingID: meeting.id) || !canGenerate)
            }

            Group {
                if meetingStore.isEnhancing(meetingID: meeting.id) && meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ProgressView("正在生成结构化纪要...")
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Once enough transcript is available, the meeting will condense into a cleaner note here. You can also trigger a refresh manually.")
                        .font(.body)
                        .foregroundStyle(AppTheme.mutedInk)
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
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
        }
    }

    private var canGenerate: Bool {
        !meeting.userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionTitle: String {
        meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generate" : "Refresh"
    }
}
