import PhotosUI
import SwiftUI

private struct MeetingNoteAttachmentViewerImage: Identifiable {
    let id = UUID()
    let image: UIImage
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
                    .foregroundStyle(AppTheme.surface)
                    .frame(width: 18, height: 18)
                    .background(AppTheme.ink)
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
                    .foregroundStyle(AppTheme.ink)

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
                .foregroundStyle(AppTheme.ink)
                .frame(width: 32, height: 32)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }
}
