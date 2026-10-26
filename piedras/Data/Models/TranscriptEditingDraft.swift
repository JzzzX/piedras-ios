import Foundation

struct TranscriptEditingDraft: Identifiable, Equatable {
    let id: String
    let rawSpeaker: String
    var text: String
    let startTime: Double
    let endTime: Double
    let isFinal: Bool
    let orderIndex: Int
    let confidence: Double?

    init(
        id: String,
        rawSpeaker: String,
        text: String,
        startTime: Double,
        endTime: Double,
        isFinal: Bool,
        orderIndex: Int,
        confidence: Double?
    ) {
        self.id = id
        self.rawSpeaker = rawSpeaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
        self.orderIndex = orderIndex
        self.confidence = confidence
    }

    init(segment: TranscriptSegment) {
        self.init(
            id: segment.id,
            rawSpeaker: segment.speaker,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            isFinal: segment.isFinal,
            orderIndex: segment.orderIndex,
            confidence: segment.confidence
        )
    }
}
