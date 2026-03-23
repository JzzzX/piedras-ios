import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AnnotationStore {
    private let repository: AnnotationRepository

    /// The segment ID currently being annotated (expanded editor is visible).
    var activeSegmentID: String?

    /// Error surfaced to the view layer.
    var lastErrorMessage: String?

    init(repository: AnnotationRepository) {
        self.repository = repository
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
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeImage(fileName: String, from segment: TranscriptSegment, meetingID: String) {
        guard let annotation = segment.annotation else { return }
        AnnotationImageStorage.deleteImage(
            meetingID: meetingID,
            annotationID: annotation.id,
            fileName: fileName
        )
        repository.removeImageFileName(fileName, from: annotation)
        repository.deleteAnnotationIfEmpty(annotation)
        persistChanges()
    }

    // MARK: - Deletion

    func deleteAnnotation(for segment: TranscriptSegment, meetingID: String) {
        guard let annotation = segment.annotation else { return }
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
}
