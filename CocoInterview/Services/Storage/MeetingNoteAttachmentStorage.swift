import UIKit

enum MeetingNoteAttachmentStorage {
    private static let fileManager = FileManager.default

    static func directoryURL(meetingID: String) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("note-attachments", isDirectory: true)
            .appendingPathComponent(meetingID, isDirectory: true)
    }

    static func imageURL(meetingID: String, fileName: String) -> URL {
        directoryURL(meetingID: meetingID)
            .appendingPathComponent(fileName)
    }

    static func cachedFileName(
        remoteAttachmentID: String,
        mimeType: String?,
        originalName: String?
    ) -> String {
        if let originalName {
            let ext = URL(fileURLWithPath: originalName).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ext.isEmpty {
                return "\(remoteAttachmentID).\(ext)"
            }
        }

        if let mimeType {
            let normalized = mimeType.lowercased()
            if normalized.contains("png") {
                return "\(remoteAttachmentID).png"
            }
            if normalized.contains("heic") {
                return "\(remoteAttachmentID).heic"
            }
        }

        return "\(remoteAttachmentID).jpg"
    }

    @discardableResult
    static func saveImage(
        _ image: UIImage,
        meetingID: String,
        compressionQuality: CGFloat = 0.82
    ) throws -> String {
        let directory = directoryURL(meetingID: meetingID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw AnnotationImageStorageError.compressionFailed
        }

        let fileName = "\(UUID().uuidString.lowercased()).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    static func loadImage(meetingID: String, fileName: String) -> UIImage? {
        let url = imageURL(meetingID: meetingID, fileName: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    static func saveData(
        _ data: Data,
        meetingID: String,
        preferredFileName: String
    ) throws -> String {
        let directory = directoryURL(meetingID: meetingID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFileName = fileName.isEmpty ? UUID().uuidString.lowercased() : fileName
        let fileURL = directory.appendingPathComponent(normalizedFileName)
        try data.write(to: fileURL, options: .atomic)
        return normalizedFileName
    }

    static func deleteImage(meetingID: String, fileName: String) {
        let url = imageURL(meetingID: meetingID, fileName: fileName)
        try? fileManager.removeItem(at: url)
    }

    static func deleteAllAttachments(meetingID: String) {
        let directory = directoryURL(meetingID: meetingID)
        try? fileManager.removeItem(at: directory)
    }
}
