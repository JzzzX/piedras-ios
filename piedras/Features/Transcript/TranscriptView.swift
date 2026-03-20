import SwiftUI

struct TranscriptView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if sentences.isEmpty {
                emptyState
            } else {
                ForEach(sentences) { sentence in
                    sentenceRow(sentence)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: recordingSessionStore.currentPartial)
        .animation(.easeOut(duration: 0.18), value: meeting.orderedSegments.count)
        .textSelection(.enabled)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            skeletonLine(width: 44, height: 8, opacity: 0.22)
            skeletonLine(width: nil, height: 14, opacity: 0.16)
            skeletonLine(width: 240, height: 14, opacity: 0.14)

            skeletonLine(width: 44, height: 8, opacity: 0.20)
                .padding(.top, 2)
            skeletonLine(width: nil, height: 14, opacity: 0.14)
            skeletonLine(width: 210, height: 14, opacity: 0.12)
        }
        .padding(.top, 2)
    }

    private func sentenceRow(_ sentence: TranscriptSentence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(sentence.timeLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
                    .accessibilityIdentifier("TranscriptTimestamp")

                if sentence.isLive {
                    Rectangle()
                        .fill(AppTheme.highlight)
                        .frame(width: 4, height: 4)

                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.highlight)
                }
            }

            Text(sentence.text)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .lineSpacing(AppTheme.editorialBodyLineSpacing)
                .foregroundStyle(AppTheme.ink.opacity(sentence.isLive ? 0.84 : 1))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func skeletonLine(width: CGFloat?, height: CGFloat, opacity: Double) -> some View {
        Rectangle()
            .fill(AppTheme.border.opacity(opacity))
            .frame(width: width, height: height)
    }

    private var sentences: [TranscriptSentence] {
        var items = meeting.orderedSegments.compactMap { segment -> TranscriptSentence? in
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }

            return TranscriptSentence(
                id: segment.id,
                timeLabel: timeLabel(for: segment.startTime),
                text: trimmedText,
                isLive: false
            )
        }

        if showsLiveSentence {
            items.append(
                TranscriptSentence(
                    id: "live-\(meeting.id)",
                    timeLabel: recordingSessionStore.durationSeconds.mmss,
                    text: recordingSessionStore.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines),
                    isLive: true
                )
            )
        }

        if showsImportedFilePartial {
            items.append(
                TranscriptSentence(
                    id: "file-live-\(meeting.id)",
                    timeLabel: fileTranscriptionTimeLabel,
                    text: meetingStore.fileTranscriptionPartial(meetingID: meeting.id)
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    isLive: true
                )
            )
        }

        return items
    }

    private var showsLiveSentence: Bool {
        recordingSessionStore.meetingID == meeting.id &&
            !recordingSessionStore.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsImportedFilePartial: Bool {
        meetingStore.isFileTranscribing(meetingID: meeting.id) &&
            !meetingStore.fileTranscriptionPartial(meetingID: meeting.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private var fileTranscriptionTimeLabel: String {
        guard let status = meetingStore.fileTranscriptionStatus(meetingID: meeting.id),
              case let .transcribing(elapsed, _) = status.phase else {
            return meeting.durationLabel
        }

        return elapsed.mmss
    }

    private func timeLabel(for startTime: Double) -> String {
        let normalizedSeconds = max(0, (startTime - baseTime) / 1000)
        return TimeInterval(normalizedSeconds).mmss
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

private struct TranscriptSentence: Identifiable {
    let id: String
    let timeLabel: String
    let text: String
    let isLive: Bool
}
