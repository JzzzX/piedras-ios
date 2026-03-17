import SwiftUI

struct TranscriptView: View {
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transcript")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.ink)

                    Text("Live capture from the meeting.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtleInk)
                }

                Spacer()

                Text(meeting.transcriptSummaryLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.accentSoft, in: Capsule())
            }

            if recordingSessionStore.meetingID == meeting.id && !recordingSessionStore.currentPartial.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.highlight)
                        .textCase(.uppercase)

                    Text(recordingSessionStore.currentPartial)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.highlightSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if meeting.orderedSegments.isEmpty {
                Text("No transcript yet. Start recording or wait for the current session to finish pushing final segments.")
                    .font(.body)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 14) {
                    ForEach(meeting.orderedSegments) { segment in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(segment.speaker)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.subtleInk)
                                    .textCase(.uppercase)

                                Spacer()

                                Text(segment.timeRangeLabel(relativeTo: baseTime))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppTheme.subtleInk)
                            }

                            Text(segment.text)
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
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

    private var baseTime: Double {
        guard let firstSegment = meeting.orderedSegments.first else {
            return 0
        }

        if firstSegment.startTime > 86_400_000 {
            return min(firstSegment.startTime, meeting.date.timeIntervalSince1970 * 1000)
        }

        return 0
    }
}
