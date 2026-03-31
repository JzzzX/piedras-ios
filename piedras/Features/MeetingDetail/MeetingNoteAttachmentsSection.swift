import PhotosUI
import SwiftUI

private struct MeetingNoteAttachmentViewerImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct RecordingAttachmentDockMetrics: Equatable {
    static let itemsPerRow = 4
    static let maxVisibleRows = 2
    static let itemSide: CGFloat = 58
    static let itemSpacing: CGFloat = 8

    let isVisible: Bool
    let visibleRowCount: Int
    let showsInternalScroll: Bool

    static func forAttachmentCount(_ count: Int) -> Self {
        let normalizedCount = max(count, 0)
        guard normalizedCount > 0 else {
            return Self(isVisible: false, visibleRowCount: 0, showsInternalScroll: false)
        }

        let rowCount = Int(ceil(Double(normalizedCount) / Double(itemsPerRow)))
        let visibleRowCount = min(max(rowCount, 1), maxVisibleRows)
        return Self(
            isVisible: true,
            visibleRowCount: visibleRowCount,
            showsInternalScroll: rowCount > maxVisibleRows
        )
    }

    var gridHeight: CGFloat {
        guard visibleRowCount > 0 else { return 0 }
        let spacing = CGFloat(max(visibleRowCount - 1, 0)) * Self.itemSpacing
        return CGFloat(visibleRowCount) * Self.itemSide + spacing
    }

    func containerHeight(showsRefreshHint: Bool) -> CGFloat {
        let hintHeight: CGFloat = showsRefreshHint ? 22 : 0
        return 20 + 18 + 10 + gridHeight + hintHeight + 18
    }
}

private struct MeetingNoteAttachmentTile: View {
    let meetingID: String
    let fileName: String
    let onTap: (UIImage) -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = MeetingNoteAttachmentStorage.loadImage(meetingID: meetingID, fileName: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.backgroundSecondary)
                    .onTapGesture {
                        onTap(image)
                    }
            } else {
                Rectangle()
                    .fill(AppTheme.backgroundSecondary)
                    .frame(height: 92)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.subtleInk)
                    }
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.primaryActionForeground)
                    .frame(width: 18, height: 18)
                    .background(AppTheme.primaryActionFill)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }
}

private struct RecordingMeetingNoteAttachmentTile: View {
    let meetingID: String
    let fileName: String
    let sideLength: CGFloat
    let onTap: (UIImage) -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = MeetingNoteAttachmentStorage.loadImage(meetingID: meetingID, fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: sideLength, height: sideLength)
                        .clipped()
                        .onTapGesture {
                            onTap(image)
                        }
                } else {
                    Rectangle()
                        .fill(AppTheme.backgroundSecondary)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.subtleInk)
                        }
                }
            }
            .frame(width: sideLength, height: sideLength)
            .background(AppTheme.backgroundSecondary)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.primaryActionForeground)
                    .frame(width: 18, height: 18)
                    .background(AppTheme.primaryActionFill)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .frame(width: sideLength, height: sideLength)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }
}

struct MeetingNoteAttachmentsSection: View {
    let meeting: Meeting
    let showsInlineAddActions: Bool
    let canAddMore: Bool
    let showsRefreshHint: Bool
    let onTakePhoto: () -> Void
    let onSelectPhotos: () -> Void
    let onDelete: (String) -> Void

    @State private var viewingImage: MeetingNoteAttachmentViewerImage?

    private let columns = [
        GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 10, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if meeting.noteAttachmentFileNames.isEmpty {
                Text(AppStrings.current.noteAttachmentsHint)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(meeting.noteAttachmentFileNames, id: \.self) { fileName in
                        MeetingNoteAttachmentTile(
                            meetingID: meeting.id,
                            fileName: fileName,
                            onTap: { image in
                                viewingImage = MeetingNoteAttachmentViewerImage(image: image)
                            },
                            onDelete: {
                                onDelete(fileName)
                            }
                        )
                    }
                }

                if showsRefreshHint {
                    Text(AppStrings.current.imageTextRefreshHint)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface.opacity(0.76))
        .overlay(
            Rectangle()
                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
        )
        .fullScreenCover(item: $viewingImage) { item in
            AnnotationImageViewer(image: item.image)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.current.noteAttachmentsTitle)
                    .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.brandInk)

                Text("\(meeting.noteAttachmentFileNames.count) / 10")
                    .font(AppTheme.dataFont(size: 11))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer(minLength: 0)

            if showsInlineAddActions {
                HStack(spacing: 8) {
                    attachmentActionButton(
                        systemName: "camera",
                        label: AppStrings.current.annotationTakePhoto,
                        isDisabled: !canAddMore,
                        action: onTakePhoto
                    )
                    attachmentActionButton(
                        systemName: "photo.on.rectangle.angled",
                        label: AppStrings.current.annotationAddImage,
                        isDisabled: !canAddMore,
                        action: onSelectPhotos
                    )
                }
            }
        }
    }

    private func attachmentActionButton(
        systemName: String,
        label: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.brandInk)
                .frame(width: 32, height: 32)
                .background(AppTheme.selectedChromeFill)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.selectedChromeBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }
}

struct RecordingMeetingNoteAttachmentsDock: View {
    let meeting: Meeting
    let showsRefreshHint: Bool
    let onDelete: (String) -> Void

    @State private var viewingImage: MeetingNoteAttachmentViewerImage?

    private let metrics: RecordingAttachmentDockMetrics
    private let columns: [GridItem]

    init(
        meeting: Meeting,
        showsRefreshHint: Bool,
        onDelete: @escaping (String) -> Void
    ) {
        self.meeting = meeting
        self.showsRefreshHint = showsRefreshHint
        self.onDelete = onDelete
        self.metrics = RecordingAttachmentDockMetrics.forAttachmentCount(meeting.noteAttachmentFileNames.count)
        self.columns = Array(
            repeating: GridItem(.fixed(RecordingAttachmentDockMetrics.itemSide), spacing: RecordingAttachmentDockMetrics.itemSpacing),
            count: RecordingAttachmentDockMetrics.itemsPerRow
        )
    }

    var body: some View {
        if metrics.isVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppStrings.current.noteAttachmentsTitle)
                            .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.brandInk)

                        Text("\(meeting.noteAttachmentFileNames.count) / 10")
                            .font(AppTheme.dataFont(size: 11))
                            .foregroundStyle(AppTheme.subtleInk)
                    }

                    Spacer(minLength: 0)
                }

                ScrollView(.vertical, showsIndicators: metrics.showsInternalScroll) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: RecordingAttachmentDockMetrics.itemSpacing) {
                        ForEach(meeting.noteAttachmentFileNames, id: \.self) { fileName in
                            RecordingMeetingNoteAttachmentTile(
                                meetingID: meeting.id,
                                fileName: fileName,
                                sideLength: RecordingAttachmentDockMetrics.itemSide,
                                onTap: { image in
                                    viewingImage = MeetingNoteAttachmentViewerImage(image: image)
                                },
                                onDelete: {
                                    onDelete(fileName)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: metrics.gridHeight)

                if showsRefreshHint {
                    Text(AppStrings.current.imageTextRefreshHint)
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(AppTheme.surface.opacity(0.96))
            .overlay(
                Rectangle()
                    .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
            )
            .fullScreenCover(item: $viewingImage) { item in
                AnnotationImageViewer(image: item.image)
            }
        }
    }
}
