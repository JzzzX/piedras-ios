import UIKit

enum AnnotationImageStorageError: LocalizedError {
    case compressionFailed
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "图片压缩失败。"
        case .directoryCreationFailed: return "无法创建图片存储目录。"
        }
    }
}

enum AnnotationImageStorage {
    private static let fileManager = FileManager.default

    /// Base directory: Documents/annotations/{meetingID}/{annotationID}/
    static func directoryURL(meetingID: String, annotationID: String) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("annotations", isDirectory: true)
            .appendingPathComponent(meetingID, isDirectory: true)
            .appendingPathComponent(annotationID, isDirectory: true)
    }

    static func imageURL(meetingID: String, annotationID: String, fileName: String) -> URL {
        directoryURL(meetingID: meetingID, annotationID: annotationID)
            .appendingPathComponent(fileName)
    }

    /// Save a UIImage as JPEG, return the filename (not full path).
    @discardableResult
    static func saveImage(
        _ image: UIImage,
        meetingID: String,
        annotationID: String,
        compressionQuality: CGFloat = 0.82
    ) throws -> String {
        let directory = directoryURL(meetingID: meetingID, annotationID: annotationID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw AnnotationImageStorageError.compressionFailed
        }

        let fileName = "\(UUID().uuidString.lowercased()).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    /// Load UIImage for a given filename.
    static func loadImage(meetingID: String, annotationID: String, fileName: String) -> UIImage? {
        let url = imageURL(meetingID: meetingID, annotationID: annotationID, fileName: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Delete a single image file.
    static func deleteImage(meetingID: String, annotationID: String, fileName: String) {
        let url = imageURL(meetingID: meetingID, annotationID: annotationID, fileName: fileName)
        try? fileManager.removeItem(at: url)
    }

    /// Delete all images for an annotation.
    static func deleteAllImages(meetingID: String, annotationID: String) {
        let directory = directoryURL(meetingID: meetingID, annotationID: annotationID)
        try? fileManager.removeItem(at: directory)
    }

    /// Delete all annotations for a meeting (called on meeting deletion).
    static func deleteAllAnnotations(meetingID: String) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let meetingDir = documents
            .appendingPathComponent("annotations", isDirectory: true)
            .appendingPathComponent(meetingID, isDirectory: true)
        try? fileManager.removeItem(at: meetingDir)
    }
}
