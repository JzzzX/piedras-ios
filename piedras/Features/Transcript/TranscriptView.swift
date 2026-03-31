import SwiftUI

struct TranscriptView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(RecordingSessionStore.self) private var recordingSessionStore
    @Environment(AnnotationStore.self) private var annotationStore

    let meeting: Meeting
    @State private var renamingSpeakerKey: String?
    @State private var speakerNameDraft = ""

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
        .alert(AppStrings.current.renameSpeaker, isPresented: isShowingSpeakerRenameAlert) {
            TextField(AppStrings.current.speakerNamePlaceholder, text: $speakerNameDraft)
                .accessibilityIdentifier("TranscriptSpeakerRenameField")
            Button(AppStrings.current.cancel, role: .cancel) {
                dismissSpeakerRename()
            }
            Button(AppStrings.current.save) {
                commitSpeakerRename()
            }
            .accessibilityIdentifier("TranscriptSpeakerRenameSaveButton")
        } message: {
            Text(AppStrings.current.renameSpeakerPrompt)
        }
    }

    // MARK: - Sentence Row

    private func sentenceRow(_ sentence: TranscriptSentence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let speakerLabel = sentence.speakerLabel {
                    speakerLabelView(sentence: sentence, speakerLabel: speakerLabel)
                }

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

    @ViewBuilder
    private func speakerLabelView(sentence: TranscriptSentence, speakerLabel: String) -> some View {
        if sentence.canRenameSpeaker {
            Button {
                beginSpeakerRename(for: sentence)
            } label: {
                speakerBadge(label: speakerLabel, isEditable: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("TranscriptSpeakerButton")
        } else {
            speakerBadge(label: speakerLabel, isEditable: false)
        }
    }

    private func speakerBadge(label: String, isEditable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppTheme.dataFont(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.brandInk)

            if isEditable {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(AppTheme.selectedChromeFill)
        .overlay(
            Rectangle()
                .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.subtleBorderWidth)
        )
    }

    // MARK: - Annotation Badges

    @ViewBuilder
    private func annotationBadges(_ annotation: SegmentAnnotation) -> some View {
        HStack(spacing: 4) {
            if annotation.hasComment {
                Image(systemName: "text.quote")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.brandInkMuted)
            }
            if annotation.hasImages {
                HStack(spacing: 2) {
                    Image(systemName: "photo")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.brandInkMuted)
                    if annotation.imageFileNames.count > 1 {
                        Text("\(annotation.imageFileNames.count)")
                            .font(AppTheme.dataFont(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.brandInkMuted)
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

            return TranscriptSentence.segment(
                segment,
                in: meeting,
                timeLabel: timeLabel(for: segment.startTime)
            )
        }

        if showsLiveSentence {
            items.append(
                TranscriptSentence(
                    id: "live-\(meeting.id)",
                    timeLabel: recordingSessionStore.durationSeconds.mmss,
                    text: recordingSessionStore.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines),
                    isLive: true,
                    segment: nil,
                    speakerLabel: nil,
                    speakerKey: nil
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
                    segment: nil,
                    speakerLabel: nil,
                    speakerKey: nil
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

    private var isShowingSpeakerRenameAlert: Binding<Bool> {
        Binding(
            get: { renamingSpeakerKey != nil },
            set: { isPresented in
                if !isPresented {
                    dismissSpeakerRename()
                }
            }
        )
    }

    private func beginSpeakerRename(for sentence: TranscriptSentence) {
        guard let speakerKey = sentence.speakerKey else { return }
        renamingSpeakerKey = speakerKey
        speakerNameDraft = meeting.speakers[speakerKey] ?? ""
    }

    private func commitSpeakerRename() {
        guard let speakerKey = renamingSpeakerKey else { return }
        meetingStore.updateSpeakerDisplayName(
            speakerNameDraft,
            for: speakerKey,
            in: meeting
        )
        dismissSpeakerRename()
    }

    private func dismissSpeakerRename() {
        renamingSpeakerKey = nil
        speakerNameDraft = ""
    }
}

struct TranscriptSentence: Identifiable {
    let id: String
    let timeLabel: String
    let text: String
    let isLive: Bool
    let segment: TranscriptSegment?
    let speakerLabel: String?
    let speakerKey: String?

    var canRenameSpeaker: Bool {
        !isLive && !(speakerKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func segment(_ segment: TranscriptSegment, in meeting: Meeting, timeLabel: String) -> TranscriptSentence {
        TranscriptSentence(
            id: segment.id,
            timeLabel: timeLabel,
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
            isLive: false,
            segment: segment,
            speakerLabel: meeting.displayName(forSpeaker: segment.speaker),
            speakerKey: segment.speaker
        )
    }
}
