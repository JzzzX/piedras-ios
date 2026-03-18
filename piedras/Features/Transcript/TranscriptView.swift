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
        LazyVStack(alignment: .leading, spacing: 30) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.22), value: recordingSessionStore.currentPartial)
        .animation(.easeOut(duration: 0.22), value: meeting.orderedSegments.count)
        .textSelection(.enabled)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            skeletonLine(width: 46, height: 9, opacity: 0.26)
            skeletonLine(width: nil, height: 14, opacity: 0.18)
            skeletonLine(width: nil, height: 14, opacity: 0.16)
            skeletonLine(width: 260, height: 14, opacity: 0.14)

            skeletonLine(width: 46, height: 9, opacity: 0.22)
                .padding(.top, 4)
            skeletonLine(width: nil, height: 14, opacity: 0.16)
            skeletonLine(width: nil, height: 14, opacity: 0.14)
            skeletonLine(width: 210, height: 14, opacity: 0.12)
        }
        .padding(.top, 2)
    }

    private func skeletonLine(width: CGFloat?, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppTheme.documentHairline.opacity(opacity))
            .frame(width: width, height: height)
    }

    private func paragraphRow(
        timeLabel: String,
        speaker: String,
        text: String,
        isLive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.subtleInk)

                if isLive {
                    Circle()
                        .fill(AppTheme.highlight)
                        .frame(width: 5, height: 5)

                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.highlight)
                } else if let speakerLabel = speakerLabel(for: speaker) {
                    Text(speakerLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(1)
                }
            }

            Text(text)
                .font(.body)
                .lineSpacing(11)
                .foregroundStyle(isLive ? AppTheme.mutedInk : AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    .joined(separator: "\n\n")
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
        switch meeting.recordingMode {
        case .microphone:
            return ""
        case .fileMix:
            return "Mixed audio"
        }
    }

    private func timeLabel(for startTime: Double) -> String {
        let normalizedMilliseconds = max(0, (startTime - baseTime) / 1000)
        return TimeInterval(normalizedMilliseconds).mmss
    }

    private func speakerLabel(for speaker: String) -> String? {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered == "speaker" || lowered == "mic" || lowered == "microphone" || trimmed == "麦克风" {
            return nil
        }

        return trimmed
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
