import SwiftUI

struct TranscriptView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore
    @Environment(AnnotationStore.self) private var annotationStore

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
    }

    // MARK: - Sentence Row

    private func sentenceRow(_ sentence: TranscriptSentence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(sentence.timeLabel)
                    .font(AppTheme.dataFont(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.subtleInk)
                    .accessibilityIdentifier("TranscriptTimestamp")

                if sentence.isLive {
                    Rectangle()
                        .fill(AppTheme.highlight)
                        .frame(width: 4, height: 4)

                    Text("LIVE")
                        .font(AppTheme.dataFont(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.highlight)
                }

                Spacer(minLength: 0)

                // Annotation indicator badges (collapsed state)
                if let segment = sentence.segment,
                   let annotation = segment.annotation,
                   annotation.hasContent {
                    annotationBadges(annotation)
                }
            }

            Text(sentence.text)
                .font(AppTheme.bodyFont(size: 16))
                .lineSpacing(AppTheme.editorialBodyLineSpacing)
                .foregroundStyle(AppTheme.ink.opacity(sentence.isLive ? 0.84 : 1))
                .fixedSize(horizontal: false, vertical: true)

            // Expanded inline annotation editor
            if let segment = sentence.segment,
               annotationStore.activeSegmentID == segment.id {
                SegmentAnnotationEditor(
                    segment: segment,
                    meetingID: meeting.id
                )
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let segment = sentence.segment, !sentence.isLive else { return }
            handleSegmentTap(segment)
        }
    }

    // MARK: - Annotation Badges

    @ViewBuilder
    private func annotationBadges(_ annotation: SegmentAnnotation) -> some View {
        HStack(spacing: 4) {
            if annotation.hasComment {
                Image(systemName: "text.quote")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.subtleInk)
            }
            if annotation.hasImages {
                HStack(spacing: 2) {
                    Image(systemName: "photo")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.subtleInk)
                    if annotation.imageFileNames.count > 1 {
                        Text("\(annotation.imageFileNames.count)")
                            .font(AppTheme.dataFont(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.subtleInk)
                    }
                }
            }
        }
    }

    // MARK: - Tap Handler

    private func handleSegmentTap(_ segment: TranscriptSegment) {
        withAnimation(.easeOut(duration: 0.18)) {
            annotationStore.toggleEditor(for: segment.id)
        }
    }

    // MARK: - Empty State

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

    private func skeletonLine(width: CGFloat?, height: CGFloat, opacity: Double) -> some View {
        Rectangle()
            .fill(AppTheme.border.opacity(opacity))
            .frame(width: width, height: height)
    }

    // MARK: - Sentences

    private var sentences: [TranscriptSentence] {
        var items = meeting.orderedSegments.compactMap { segment -> TranscriptSentence? in
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }

            return TranscriptSentence(
                id: segment.id,
                timeLabel: timeLabel(for: segment.startTime),
                text: trimmedText,
                isLive: false,
                segment: segment
            )
        }

        if showsLiveSentence {
            items.append(
                TranscriptSentence(
                    id: "live-\(meeting.id)",
                    timeLabel: recordingSessionStore.durationSeconds.mmss,
                    text: recordingSessionStore.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines),
                    isLive: true,
                    segment: nil
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
                    isLive: true,
                    segment: nil
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
    let segment: TranscriptSegment?
}
