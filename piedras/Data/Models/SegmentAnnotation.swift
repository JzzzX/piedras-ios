import Foundation
import SwiftData

enum AnnotationImageTextStatus: String, Codable, CaseIterable {
    case idle
    case pending
    case ready
    case failed
}

@Model
final class SegmentAnnotation {
    @Attribute(.unique) var id: String
    var comment: String
    var imageFileNames: [String]
    @Attribute(originalName: "imageTextContext")
    private var imageTextContextValue: String?
    @Attribute(originalName: "imageTextStatusRaw")
    private var imageTextStatusRawValue: String?
    var imageTextUpdatedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var segment: TranscriptSegment?

    init(
        id: String = UUID().uuidString.lowercased(),
        comment: String = "",
        imageFileNames: [String] = [],
        imageTextContext: String = "",
        imageTextStatus: AnnotationImageTextStatus = .idle,
        imageTextUpdatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.comment = comment
        self.imageFileNames = imageFileNames
        self.imageTextContextValue = imageTextContext
        self.imageTextStatusRawValue = imageTextStatus.rawValue
        self.imageTextUpdatedAt = imageTextUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var imageTextContext: String {
        get { imageTextContextValue ?? "" }
        set { imageTextContextValue = newValue }
    }

    var imageTextStatus: AnnotationImageTextStatus {
        get { AnnotationImageTextStatus(rawValue: imageTextStatusRawValue ?? "") ?? .idle }
        set { imageTextStatusRawValue = newValue.rawValue }
    }

    var hasComment: Bool {
        !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasImages: Bool {
        !imageFileNames.isEmpty
    }

    var hasImageText: Bool {
        !imageTextContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasContent: Bool {
        hasComment || hasImages
    }
}
