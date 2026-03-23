import Foundation
import SwiftData

@Model
final class SegmentAnnotation {
    @Attribute(.unique) var id: String
    var comment: String
    var imageFileNames: [String]
    var createdAt: Date
    var updatedAt: Date
    var segment: TranscriptSegment?

    init(
        id: String = UUID().uuidString.lowercased(),
        comment: String = "",
        imageFileNames: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.comment = comment
        self.imageFileNames = imageFileNames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var hasComment: Bool {
        !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasImages: Bool {
        !imageFileNames.isEmpty
    }

    var hasContent: Bool {
        hasComment || hasImages
    }
}
