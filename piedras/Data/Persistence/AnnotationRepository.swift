import Foundation
import SwiftData

@MainActor
final class AnnotationRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func annotation(for segment: TranscriptSegment) -> SegmentAnnotation? {
        segment.annotation
    }

    @discardableResult
    func ensureAnnotation(for segment: TranscriptSegment) -> SegmentAnnotation {
        if let existing = segment.annotation {
            return existing
        }
        let annotation = SegmentAnnotation()
        annotation.segment = segment
        segment.annotation = annotation
        modelContext.insert(annotation)
        return annotation
    }

    func updateComment(_ comment: String, for annotation: SegmentAnnotation) {
        annotation.comment = comment
        annotation.updatedAt = .now
    }

    func addImageFileName(_ fileName: String, to annotation: SegmentAnnotation) {
        annotation.imageFileNames.append(fileName)
        annotation.updatedAt = .now
    }

    func removeImageFileName(_ fileName: String, from annotation: SegmentAnnotation) {
        annotation.imageFileNames.removeAll { $0 == fileName }
        annotation.updatedAt = .now
    }

    func updateImageText(
        _ text: String,
        status: AnnotationImageTextStatus,
        updatedAt: Date?,
        for annotation: SegmentAnnotation
    ) {
        annotation.imageTextContext = text
        annotation.imageTextStatus = status
        annotation.imageTextUpdatedAt = updatedAt
        annotation.updatedAt = .now
    }

    func clearImageText(for annotation: SegmentAnnotation) {
        updateImageText("", status: .idle, updatedAt: nil, for: annotation)
    }

    func deleteAnnotation(_ annotation: SegmentAnnotation) {
        modelContext.delete(annotation)
    }

    func deleteAnnotationIfEmpty(_ annotation: SegmentAnnotation) {
        guard !annotation.hasContent else { return }
        modelContext.delete(annotation)
    }

    func fetchAnnotationsNeedingImageTextBackfill() throws -> [SegmentAnnotation] {
        let descriptor = FetchDescriptor<SegmentAnnotation>()
        return try modelContext.fetch(descriptor).filter { annotation in
            annotation.hasImages
                && (annotation.imageTextUpdatedAt == nil
                    || annotation.imageTextStatus == .pending)
        }
    }

    func save() throws {
        try modelContext.save()
    }
}
