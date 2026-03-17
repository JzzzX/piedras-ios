import SwiftUI

extension Meeting {
    var durationLabel: String {
        guard durationSeconds > 0 else { return "未录音" }
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    var previewText: String {
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

    var syncStateLabel: String {
        switch syncState {
        case .pending:
            return "待同步"
        case .syncing:
            return "同步中"
        case .synced:
            return "已同步"
        case .failed:
            return "同步失败"
        case .deleted:
            return "待删除"
        }
    }

    var statusLabel: String {
        switch status {
        case .idle:
            return "待开始"
        case .recording:
            return "录音中"
        case .paused:
            return "已暂停"
        case .ended:
            return "已结束"
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
}

extension TranscriptSegment {
    func timeRangeLabel(relativeTo baseTime: Double = 0) -> String {
        let startSeconds = Int(max(0, (startTime - baseTime) / 1000))
        let endSeconds = Int(max(Double(startSeconds), (endTime - baseTime) / 1000))
        return "\(startSeconds)s - \(endSeconds)s"
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
