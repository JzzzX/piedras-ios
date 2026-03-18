import SwiftUI

private struct TranscriptParagraph: Identifiable {
    let id: String
    let speaker: String
    let startTime: Double
    let text: String
}

struct TranscriptView: View {
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            if paragraphs.isEmpty && !showsLiveParagraph {
                emptyState
            } else {
                ForEach(paragraphs) { paragraph in
                    paragraphRow(
                        timeLabel: timeLabel(for: paragraph.startTime),
                        speaker: paragraph.speaker,
                        text: paragraph.text,
                        isLive: false
                    )
                }

                if showsLiveParagraph {
                    paragraphRow(
                        timeLabel: recordingSessionStore.durationSeconds.mmss,
                        speaker: liveSpeakerName,
                        text: recordingSessionStore.currentPartial,
                        isLive: true
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: recordingSessionStore.currentPartial)
        .animation(.easeOut(duration: 0.22), value: meeting.orderedSegments.count)
        .textSelection(.enabled)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.documentHairline.opacity(0.32))
                .frame(width: 140, height: 10)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.documentHairline.opacity(0.22))
                .frame(height: 11)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.documentHairline.opacity(0.18))
                .frame(height: 11)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.documentHairline.opacity(0.14))
                .frame(width: 210, height: 11)
        }
        .padding(.top, 6)
    }

    private func paragraphRow(
        timeLabel: String,
        speaker: String,
        text: String,
        isLive: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.subtleInk)

                if isLive {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.highlight)
                }
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                (Text("\(displaySpeakerName(speaker)): ")
                    .fontWeight(.semibold)
                 + Text(text))
                    .font(.body)
                    .lineSpacing(8)
                    .foregroundStyle(isLive ? AppTheme.mutedInk : AppTheme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, isLive ? 2 : 0)
    }

    private var paragraphs: [TranscriptParagraph] {
        var grouped: [TranscriptParagraph] = []

        for segment in meeting.orderedSegments {
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }

            if let last = grouped.last,
               last.speaker == segment.speaker {
                let mergedText = [last.text, trimmedText]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                grouped[grouped.count - 1] = TranscriptParagraph(
                    id: last.id + "-" + segment.id,
                    speaker: last.speaker,
                    startTime: last.startTime,
                    text: mergedText
                )
            } else {
                grouped.append(
                    TranscriptParagraph(
                        id: segment.id,
                        speaker: segment.speaker,
                        startTime: segment.startTime,
                        text: trimmedText
                    )
                )
            }
        }

        return grouped
    }

    private var showsLiveParagraph: Bool {
        recordingSessionStore.meetingID == meeting.id && !recordingSessionStore.currentPartial.isEmpty
    }

    private var liveSpeakerName: String {
        meeting.recordingMode == .fileMix ? "混合音频" : "麦克风"
    }

    private func timeLabel(for startTime: Double) -> String {
        let normalizedMilliseconds = max(0, (startTime - baseTime) / 1000)
        return TimeInterval(normalizedMilliseconds).mmss
    }

    private func displaySpeakerName(_ speaker: String) -> String {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Speaker" : trimmed
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
