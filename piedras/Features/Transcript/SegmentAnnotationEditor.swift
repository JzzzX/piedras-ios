import PhotosUI
import SwiftUI

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct SegmentAnnotationEditor: View {
    @Environment(AnnotationStore.self) private var annotationStore

    let segment: TranscriptSegment
    let meetingID: String

    @State private var commentDraft: String = ""
    @State private var showsCamera = false
    @State private var showsPhotosPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var commentSaveTask: Task<Void, Never>?
    @State private var hasPendingChanges = false
    @State private var viewingImage: IdentifiableImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Comment input
            commentInput

            // Image thumbnails (if any)
            if let annotation = segment.annotation, !annotation.imageFileNames.isEmpty {
                annotationImageStrip(annotation)
            }

            // Action buttons
            actionButtons
        }
        .padding(12)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .onAppear {
            commentDraft = segment.annotation?.comment ?? ""
        }
        .onDisappear {
            commitPendingComment()
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraImagePicker(onImageCaptured: handleCapturedImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewingImage) { item in
            AnnotationImageViewer(image: item.image)
        }
        .photosPicker(
            isPresented: $showsPhotosPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            handleSelectedPhotos(items)
        }
    }

    // MARK: - Comment Input

    private var commentInput: some View {
        TextField(AppStrings.current.annotationCommentPlaceholder, text: $commentDraft, axis: .vertical)
            .font(AppTheme.bodyFont(size: 14))
            .foregroundStyle(AppTheme.ink)
            .lineLimit(1...6)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.background)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .onChange(of: commentDraft) { _, newValue in
                scheduleCommentSave(newValue)
            }
    }

    // MARK: - Image Strip

    private func annotationImageStrip(_ annotation: SegmentAnnotation) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(annotation.imageFileNames, id: \.self) { fileName in
                    AnnotationThumbnail(
                        meetingID: meetingID,
                        annotationID: annotation.id,
                        fileName: fileName,
                        onTap: {
                            if let image = AnnotationImageStorage.loadImage(
                                meetingID: meetingID,
                                annotationID: annotation.id,
                                fileName: fileName
                            ) {
                                viewingImage = IdentifiableImage(image: image)
                            }
                        },
                        onDelete: {
                            annotationStore.removeImage(
                                fileName: fileName,
                                from: segment,
                                meetingID: meetingID
                            )
                        }
                    )
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            annotationActionButton(
                systemName: "camera",
                label: AppStrings.current.annotationTakePhoto
            ) {
                showsCamera = true
            }

            annotationActionButton(
                systemName: "photo.on.rectangle",
                label: AppStrings.current.annotationAddImage
            ) {
                showsPhotosPicker = true
            }

            Spacer()

            // Save indicator — appears when there are pending changes
            if hasPendingChanges {
                annotationActionButton(
                    systemName: "checkmark",
                    label: AppStrings.current.save
                ) {
                    commitPendingComment()
                }
                .transition(.opacity)
            }

            annotationActionButton(
                systemName: "xmark",
                label: AppStrings.current.close
            ) {
                commitPendingComment()
                annotationStore.dismissEditor()
            }
        }
        .animation(.easeOut(duration: 0.2), value: hasPendingChanges)
    }

    private func annotationActionButton(
        systemName: String,
        label: String,
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
        .accessibilityLabel(label)
    }

    // MARK: - Persistence

    private func scheduleCommentSave(_ text: String) {
        commentSaveTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            hasPendingChanges = true
        }
        commentSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            annotationStore.updateComment(text, for: segment, meetingID: meetingID)
            withAnimation(.easeOut(duration: 0.2)) {
                hasPendingChanges = false
            }
        }
    }

    private func commitPendingComment() {
        commentSaveTask?.cancel()
        annotationStore.updateComment(commentDraft, for: segment, meetingID: meetingID)
        withAnimation(.easeOut(duration: 0.2)) {
            hasPendingChanges = false
        }
    }

    // MARK: - Image Handlers

    private func handleCapturedImage(_ image: UIImage) {
        annotationStore.addImage(image, to: segment, meetingID: meetingID)
    }

    private func handleSelectedPhotos(_ items: [PhotosPickerItem]) {
        for item in items {
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                annotationStore.addImage(image, to: segment, meetingID: meetingID)
            }
        }
        selectedPhotoItems = []
    }
}
