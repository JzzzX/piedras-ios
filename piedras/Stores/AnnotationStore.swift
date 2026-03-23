import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AnnotationStore {
    private let repository: AnnotationRepository
    private let imageTextExtractor: any AnnotationImageTextExtracting
    private var imageTextTasks: [String: Task<Void, Never>] = [:]
    private var imageTextTaskTokens: [String: UUID] = [:]

    /// The segment ID currently being annotated (expanded editor is visible).
    var activeSegmentID: String?

    /// Error surfaced to the view layer.
    var lastErrorMessage: String?

    init(
        repository: AnnotationRepository,
        imageTextExtractor: any AnnotationImageTextExtracting = VisionAnnotationImageTextExtractor()
    ) {
        self.repository = repository
        self.imageTextExtractor = imageTextExtractor
    }

    // MARK: - Comment CRUD

    func updateComment(_ comment: String, for segment: TranscriptSegment, meetingID: String) {
        let annotation = repository.ensureAnnotation(for: segment)
        repository.updateComment(comment, for: annotation)

        if !annotation.hasContent {
            repository.deleteAnnotationIfEmpty(annotation)
        }

        persistChanges()
    }

    // MARK: - Image CRUD

    func addImage(_ image: UIImage, to segment: TranscriptSegment, meetingID: String) {
        let annotation = repository.ensureAnnotation(for: segment)
        do {
            let fileName = try AnnotationImageStorage.saveImage(
                image,
                meetingID: meetingID,
                annotationID: annotation.id
            )
            repository.addImageFileName(fileName, to: annotation)
            persistChanges()
            scheduleImageTextRefresh(for: annotation, meetingID: meetingID)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeImage(fileName: String, from segment: TranscriptSegment, meetingID: String) {
        guard let annotation = segment.annotation else { return }
        let previousText = annotation.imageTextContext.trimmedForImageText
        cancelImageTextTask(for: annotation.id)
        AnnotationImageStorage.deleteImage(
            meetingID: meetingID,
            annotationID: annotation.id,
            fileName: fileName
        )
        repository.removeImageFileName(fileName, from: annotation)

        if annotation.imageFileNames.isEmpty {
            repository.clearImageText(for: annotation)
            markMeetingPendingImageTextRefreshIfNeeded(
                meeting: segment.meeting,
                previousText: previousText,
                newText: ""
            )
            repository.deleteAnnotationIfEmpty(annotation)
            persistChanges()
            return
        }

        repository.deleteAnnotationIfEmpty(annotation)
        persistChanges()
        scheduleImageTextRefresh(for: annotation, meetingID: meetingID)
    }

    // MARK: - Deletion

    func deleteAnnotation(for segment: TranscriptSegment, meetingID: String) {
        guard let annotation = segment.annotation else { return }
        cancelImageTextTask(for: annotation.id)
        AnnotationImageStorage.deleteAllImages(
            meetingID: meetingID,
            annotationID: annotation.id
        )
        repository.deleteAnnotation(annotation)
        persistChanges()
        if activeSegmentID == segment.id {
            activeSegmentID = nil
        }
    }

    /// Called when a meeting is deleted — clean up all annotation images on disk.
    func cleanupAnnotations(for meetingID: String) {
        AnnotationImageStorage.deleteAllAnnotations(meetingID: meetingID)
    }

    func backfillImageTextIfNeeded() async {
        guard let annotations = try? repository.fetchAnnotationsNeedingImageTextBackfill(),
              !annotations.isEmpty else {
            return
        }

        for annotation in annotations {
            guard let meetingID = annotation.segment?.meeting?.id else { continue }
            scheduleImageTextRefresh(for: annotation, meetingID: meetingID)
        }

        for annotation in annotations {
            await imageTextTasks[annotation.id]?.value
        }
    }

    // MARK: - UI State

    func toggleEditor(for segmentID: String) {
        if activeSegmentID == segmentID {
            activeSegmentID = nil
        } else {
            activeSegmentID = segmentID
        }
    }

    func dismissEditor() {
        activeSegmentID = nil
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    // MARK: - Private

    private func persistChanges() {
        do {
            try repository.save()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func scheduleImageTextRefresh(for annotation: SegmentAnnotation, meetingID: String) {
        cancelImageTextTask(for: annotation.id)

        let fileNames = annotation.imageFileNames
        guard !fileNames.isEmpty else {
            repository.clearImageText(for: annotation)
            persistChanges()
            return
        }

        repository.updateImageText(
            annotation.imageTextContext,
            status: .pending,
            updatedAt: annotation.imageTextUpdatedAt,
            for: annotation
        )
        persistChanges()

        let annotationID = annotation.id
        let taskToken = UUID()
        let imageURLs = fileNames.map {
            AnnotationImageStorage.imageURL(
                meetingID: meetingID,
                annotationID: annotationID,
                fileName: $0
            )
        }
        imageTextTaskTokens[annotationID] = taskToken

        imageTextTasks[annotationID] = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let extractedText = try await imageTextExtractor.extractText(from: imageURLs)
                guard !Task.isCancelled else { return }
                guard imageTextTaskTokens[annotationID] == taskToken else { return }
                applyImageText(extractedText, to: annotation)
            } catch {
                guard !Task.isCancelled else { return }
                guard imageTextTaskTokens[annotationID] == taskToken else { return }
                repository.updateImageText("", status: .failed, updatedAt: .now, for: annotation)
                persistChanges()
            }

            imageTextTasks[annotationID] = nil
            imageTextTaskTokens[annotationID] = nil
        }
    }

    private func applyImageText(_ extractedText: String, to annotation: SegmentAnnotation) {
        let normalizedText = extractedText.trimmedForImageText
        let previousText = annotation.imageTextContext.trimmedForImageText

        repository.updateImageText(
            normalizedText,
            status: .ready,
            updatedAt: .now,
            for: annotation
        )
        markMeetingPendingImageTextRefreshIfNeeded(
            meeting: annotation.segment?.meeting,
            previousText: previousText,
            newText: normalizedText
        )
        persistChanges()
    }

    private func markMeetingPendingImageTextRefreshIfNeeded(
        meeting: Meeting?,
        previousText: String,
        newText: String
    ) {
        guard previousText != newText,
              let meeting,
              !meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        meeting.hasPendingImageTextRefresh = true
        meeting.updatedAt = .now
    }

    private func cancelImageTextTask(for annotationID: String) {
        imageTextTasks[annotationID]?.cancel()
        imageTextTasks[annotationID] = nil
        imageTextTaskTokens[annotationID] = nil
    }
}

private extension String {
    var trimmedForImageText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
