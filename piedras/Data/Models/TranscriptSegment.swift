import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    @Attribute(.unique) var id: String
    var speaker: String
    var text: String
    var startTime: Double
    var endTime: Double
    var isFinal: Bool
    var orderIndex: Int
    var confidence: Double?
    var meeting: Meeting?

    init(
        id: String = UUID().uuidString.lowercased(),
        speaker: String,
        text: String,
        startTime: Double,
        endTime: Double,
        isFinal: Bool = true,
        orderIndex: Int,
        confidence: Double? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
        self.orderIndex = orderIndex
        self.confidence = confidence
    }
}
