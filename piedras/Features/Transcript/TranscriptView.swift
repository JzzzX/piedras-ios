import SwiftUI

struct TranscriptView: View {
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsLiveStrip {
                liveStrip
            }

            if meeting.orderedSegments.isEmpty {
                emptyState
            } else {
                VStack(spacing: 16) {
                    ForEach(Array(meeting.orderedSegments.enumerated()), id: \.element.id) { index, segment in
                        transcriptRow(for: segment)

                        if index < meeting.orderedSegments.count - 1 {
                            AppGlassDivider(inset: 60)
                        }
                    }
                }
            }
        }
    }

    private var liveStrip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.highlight)
                .padding(.top, 2)

            Text(recordingSessionStore.currentPartial)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AppGlassSurface(cornerRadius: 20, style: .clear, shadowOpacity: 0.03)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.subtleInk)

            Text("No transcript")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if recordingSessionStore.meetingID == meeting.id && recordingSessionStore.phase != .idle {
                Text("Listening...")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func transcriptRow(for segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(segment.timeRangeLabel(relativeTo: baseTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.subtleInk)

                Text(segment.speaker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.subtleInk)
                    .textCase(.uppercase)
            }
            .frame(width: 46, alignment: .leading)

            Text(segment.text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var showsLiveStrip: Bool {
        recordingSessionStore.meetingID == meeting.id && !recordingSessionStore.currentPartial.isEmpty
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
