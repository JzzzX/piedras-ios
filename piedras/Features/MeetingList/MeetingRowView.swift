import SwiftUI

struct MeetingRowSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let metadataPrimary: String
    let metadataDuration: String?
    let isRecording: Bool
    let showsSyncFailure: Bool
    let matchedSources: [MeetingSearchSource]

    init(meeting: Meeting, isRecording: Bool, matchedSources: [MeetingSearchSource] = []) {
        id = meeting.id
        title = meeting.displayTitle
        let metadataComponents = meeting.homeMetadataComponents()
        metadataPrimary = metadataComponents.first ?? ""
        metadataDuration = metadataComponents.dropFirst().first
        self.isRecording = isRecording
        showsSyncFailure = !isRecording && meeting.syncState == .failed
        self.matchedSources = Array(matchedSources.prefix(2))
    }
}

struct MeetingRowView: View {
    let snapshot: MeetingRowSnapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                leadingIcon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(snapshot.title)
                            .font(AppTheme.bodyFont(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        if snapshot.isRecording {
                            RetroStampLabel(text: "REC")
                        } else if snapshot.showsSyncFailure {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(snapshot.metadataPrimary)
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundStyle(AppTheme.subtleInk)
                            .lineLimit(1)

                        if let metadataDuration = snapshot.metadataDuration {
                            Text("·")
                                .font(AppTheme.bodyFont(size: 12))
                                .foregroundStyle(AppTheme.subtleInk)

                            Text(metadataDuration)
                                .font(AppTheme.dataFont(size: 12))
                                .foregroundStyle(AppTheme.subtleInk)
                                .lineLimit(1)
                        }
                    }

                    if !snapshot.matchedSources.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(snapshot.matchedSources, id: \.self) { source in
                                Text(source.label)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppTheme.subtleInk)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.background)
                                    .overlay(
                                        Rectangle()
                                            .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                                    )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(
                borderColor: snapshot.isRecording ? AppTheme.highlight : AppTheme.subtleBorderColor,
                lineWidth: snapshot.isRecording ? 1.5 : AppTheme.subtleBorderWidth
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("MeetingRow")
    }

    private var leadingIcon: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Rectangle()
                    .fill(AppTheme.iconBackground)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )

                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.caramel)
            }
            .frame(width: AppTheme.compactIconSize, height: AppTheme.compactIconSize)

            if snapshot.isRecording {
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
}
