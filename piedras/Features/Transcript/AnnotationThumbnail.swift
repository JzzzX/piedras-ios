import SwiftUI

struct AnnotationThumbnail: View {
    let meetingID: String
    let annotationID: String
    let fileName: String
    let onTap: () -> Void
    let onDelete: () -> Void

    private let size: CGFloat = 64

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = AnnotationImageStorage.loadImage(
                meetingID: meetingID,
                annotationID: annotationID,
                fileName: fileName
            ) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .onTapGesture { onTap() }
            } else {
                Rectangle()
                    .fill(AppTheme.surface)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.subtleInk)
                    }
            }

            // Delete button
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
