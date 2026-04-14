import SwiftUI

extension Meeting {
    var durationLabel: String {
        guard durationSeconds > 0 else { return AppStrings.current.notRecorded }
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    var previewText: String {
        let enhanced = enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enhanced.isEmpty {
            return enhanced
        }

        let notes = userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            return notes
        }

        let transcript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            return transcript
        }

        return ""
    }

    var displayableTranscriptText: String {
        transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasDisplayableTranscript: Bool {
        !displayableTranscriptText.isEmpty
    }

    var hasEnhanceableMaterial: Bool {
        if hasDisplayableTranscript {
            return true
        }

        if !userNotesPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if !MeetingCommentContextBuilder.noteAttachmentsContext(for: self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            return true
        }

        return !MeetingCommentContextBuilder.segmentCommentsContext(for: self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var daySectionTitle: String {
        if Calendar.current.isDateInToday(date) {
            return AppStrings.current.today
        }

        if Calendar.current.isDateInYesterday(date) {
            return AppStrings.current.yesterday
        }

        return date.formatted(.dateTime.month(.wide).day())
    }

    var detailTimestampLabel: String {
        date.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
    }

    var compactTimestampLabel: String {
        date.formatted(.dateTime.hour().minute())
    }

    func homeMetadataComponents(
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [String] {
        let isToday = calendar.isDate(date, inSameDayAs: referenceDate)
        let isYesterday = if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) {
            calendar.isDate(date, inSameDayAs: yesterday)
        } else {
            false
        }

        let leading = isToday || isYesterday
            ? compactTimestampLabel
            : date.formatted(.dateTime.month(.wide).day())

        return [leading, durationLabel]
            .filter { !$0.isEmpty }
    }

    var homeMetadataLine: String {
        homeMetadataComponents().joined(separator: " · ")
    }

    var transcriptSummaryLabel: String {
        "\(orderedSegments.count)\(AppStrings.current.segmentsTranscript)"
    }

    var transcriptCountLabel: String {
        "\(orderedSegments.count)"
    }

    var syncStateLabel: String {
        switch syncState {
        case .pending:
            return AppStrings.current.syncPending
        case .syncing:
            return AppStrings.current.syncing
        case .synced:
            return AppStrings.current.synced
        case .failed:
            return AppStrings.current.syncFailed
        case .deleted:
            return AppStrings.current.syncDeleted
        }
    }

    var statusLabel: String {
        switch status {
        case .idle:
            return AppStrings.current.statusIdle
        case .recording:
            return AppStrings.current.statusRecording
        case .paused:
            return AppStrings.current.statusPaused
        case .transcribing:
            return AppStrings.current.statusTranscribing
        case .transcriptionFailed:
            return AppStrings.current.statusTranscriptionFailed
        case .ended:
            return AppStrings.current.statusEnded
        }
    }

    var statusIconName: String {
        switch status {
        case .idle:
            return "circle.dashed"
        case .recording:
            return "record.circle"
        case .paused:
            return "pause.circle"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .transcriptionFailed:
            return "exclamationmark.circle"
        case .ended:
            return "checkmark.circle"
        }
    }

    var syncStateTint: Color {
        switch syncState {
        case .pending:
            return .orange
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .failed:
            return .red
        case .deleted:
            return .secondary
        }
    }

    var syncStateIconName: String {
        switch syncState {
        case .pending:
            return "clock.badge"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .deleted:
            return "trash.circle.fill"
        }
    }
}

extension TranscriptSegment {
    func timeRangeLabel(relativeTo baseTime: Double = 0) -> String {
        let startSeconds = Int(max(0, (startTime - baseTime) / 1000))
        let endSeconds = Int(max(Double(startSeconds), (endTime - baseTime) / 1000))
        return "\(startSeconds)s - \(endSeconds)s"
    }
}

extension RecordingPhase {
    var displayLabel: String {
        switch self {
        case .idle:
            return AppStrings.current.phaseIdle
        case .starting:
            return AppStrings.current.phaseStarting
        case .recording:
            return AppStrings.current.phaseRecording
        case .paused:
            return AppStrings.current.phasePaused
        case .stopping:
            return AppStrings.current.phaseStopping
        }
    }
}

extension ASRConnectionState {
    var displayLabel: String {
        switch self {
        case .idle:
            return AppStrings.current.asrIdle
        case .connecting:
            return AppStrings.current.asrConnecting
        case .connected:
            return AppStrings.current.asrConnected
        case .degraded:
            return AppStrings.current.asrDegraded
        case .disconnected:
            return AppStrings.current.asrDisconnected
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .degraded:
            return .orange
        case .disconnected:
            return .red
        }
    }
}

extension BackgroundTranscriptionStatus {
    var badgeLabel: String? {
        switch self {
        case .inactive:
            return nil
        case .chunking:
            return AppStrings.current.backgroundTranscribing
        case .flushing:
            return AppStrings.current.finalizingBackgroundTranscript
        case .failedNeedsRepair:
            return AppStrings.current.backgroundTranscriptRepairOnStop
        }
    }

    var bannerMessage: String? {
        switch self {
        case .inactive:
            return nil
        case .chunking:
            return AppStrings.current.backgroundTranscribing
        case .flushing:
            return AppStrings.current.finalizingBackgroundTranscript
        case .failedNeedsRepair:
            return AppStrings.current.backgroundTranscriptPendingRepair
        }
    }

    var tint: Color {
        switch self {
        case .inactive:
            return .secondary
        case .chunking, .flushing:
            return AppTheme.highlight
        case .failedNeedsRepair:
            return .red
        }
    }

    var debugLabel: String? {
        switch self {
        case .inactive:
            return nil
        case .chunking:
            return "ASR:BG"
        case .flushing:
            return "ASR:TAIL"
        case .failedNeedsRepair:
            return "ASR:FIX"
        }
    }
}

extension RecordingInputMode {
    var meetingMode: MeetingRecordingMode {
        switch self {
        case .microphone:
            return .microphone
        case .fileMix:
            return .fileMix
        }
    }
}

extension TimeInterval {
    var mmss: String {
        let totalSeconds = max(Int(self.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Int {
    var mmss: String {
        TimeInterval(self).mmss
    }
}
