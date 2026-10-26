import SwiftUI

struct CloudAudioCopiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingStore.self) private var meetingStore
    @State private var cloudAudioActionMeetingIDs: Set<String> = []

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "云端音频副本")

                        if cloudAudioMeetings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("当前还没有可管理的会议音频。")
                                    .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)

                                Text("当会议音频已上传到云端，或本机保留了可重新同步的音频时，会显示在这里。")
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundStyle(AppTheme.subtleInk)
                            }
                            .padding(16)
                            .softCard()
                        } else {
                            VStack(spacing: 10) {
                                ForEach(cloudAudioMeetings, id: \.id) { meeting in
                                    cloudAudioMeetingRow(meeting)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("云端音频副本")
                    .font(AppTheme.titleFont(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.brandInk)

                Text("删除云端副本，或恢复本机音频的云同步。")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: AppStrings.current.back, size: 40) {
                dismiss()
            }
        }
    }

    private func cloudAudioMeetingRow(_ meeting: Meeting) -> some View {
        HStack(alignment: .center, spacing: 12) {
            leadingIcon(for: meeting)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Text(meeting.displayTitle)
                        .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Text(meeting.date.formatted(.dateTime.month().day().hour().minute()))
                        .font(AppTheme.dataFont(size: 11))
                        .foregroundStyle(AppTheme.subtleInk)
                        .lineLimit(1)
                }

                Text(cloudAudioStatusText(for: meeting))
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let localAudioURL = localAudioURL(for: meeting) {
                    ShareLink(item: localAudioURL) {
                        actionIcon(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("导出本地音频")
                }

                if shouldShowDeleteRemoteAudio(for: meeting) {
                    Button {
                        Task {
                            cloudAudioActionMeetingIDs.insert(meeting.id)
                            await meetingStore.deleteRemoteAudioCopy(meetingID: meeting.id)
                            cloudAudioActionMeetingIDs.remove(meeting.id)
                        }
                    } label: {
                        actionIcon(
                            systemName: cloudAudioActionMeetingIDs.contains(meeting.id) ? "hourglass" : "trash"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(cloudAudioActionMeetingIDs.contains(meeting.id))
                    .accessibilityLabel("删除云端副本")
                } else if shouldShowEnableRemoteAudio(for: meeting) {
                    Button {
                        Task {
                            cloudAudioActionMeetingIDs.insert(meeting.id)
                            await meetingStore.enableRemoteAudioSync(meetingID: meeting.id)
                            cloudAudioActionMeetingIDs.remove(meeting.id)
                        }
                    } label: {
                        actionIcon(
                            systemName: cloudAudioActionMeetingIDs.contains(meeting.id) ? "hourglass" : "arrow.trianglehead.clockwise"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(cloudAudioActionMeetingIDs.contains(meeting.id))
                    .accessibilityLabel("恢复云端同步")
                }
            }
        }
        .padding(16)
        .softCard(fill: AppTheme.surface, borderColor: AppTheme.noteSectionRule, lineWidth: AppTheme.subtleBorderWidth)
    }

    private func actionIcon(systemName: String) -> some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.noteIconWash)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.noteSectionRule, lineWidth: AppTheme.subtleBorderWidth)
                )

            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.brandInkMuted)
        }
        .frame(width: AppTheme.compactIconSize, height: AppTheme.compactIconSize)
    }

    private func leadingIcon(for meeting: Meeting) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Rectangle()
                    .fill(AppTheme.noteIconWash)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.noteSectionRule, lineWidth: AppTheme.retroBorderWidth)
                    )

                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.brandInkMuted)
            }
            .frame(width: AppTheme.compactIconSize, height: AppTheme.compactIconSize)

            if !meeting.audioCloudSyncEnabled {
                Rectangle()
                    .fill(AppTheme.highlight)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.surface, lineWidth: 2)
                    )
                    .offset(x: 3, y: -3)
            }
        }
    }

    private var cloudAudioMeetings: [Meeting] {
        meetingStore.meetings
            .filter { meeting in
                localAudioURL(for: meeting) != nil
                    || !(meeting.audioRemotePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            .sorted { lhs, rhs in
                lhs.date > rhs.date
            }
    }

    private func localAudioURL(for meeting: Meeting) -> URL? {
        guard let path = meeting.audioLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private func cloudAudioStatusText(for meeting: Meeting) -> String {
        let hasLocal = localAudioURL(for: meeting) != nil
        let hasRemote = !(meeting.audioRemotePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        switch (hasLocal, hasRemote, meeting.audioCloudSyncEnabled) {
        case (true, true, true):
            return "本机已保存，云端已同步"
        case (true, false, true):
            return "本机已保存，等待云端同步"
        case (true, _, false):
            return "仅保存在本机，云端副本已关闭"
        case (false, true, true):
            return "仅云端保留副本"
        case (false, true, false):
            return "云端副本待清理"
        default:
            return "当前没有可用音频"
        }
    }

    private func shouldShowDeleteRemoteAudio(for meeting: Meeting) -> Bool {
        guard meeting.audioCloudSyncEnabled else { return false }
        return !(meeting.audioRemotePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func shouldShowEnableRemoteAudio(for meeting: Meeting) -> Bool {
        guard !meeting.audioCloudSyncEnabled else { return false }
        return localAudioURL(for: meeting) != nil
    }
}
