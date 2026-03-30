import Foundation

struct ASRRecognitionUtterance: Equatable {
    let text: String
    let startTimeMs: Double
    let endTimeMs: Double
    let definite: Bool
}

struct ASRRecognitionSnapshot: Equatable {
    let revision: Int
    let fullText: String
    let audioEndTimeMs: Double
    let utterances: [ASRRecognitionUtterance]
}

struct ASRLiveTranscriptReducer {
    private(set) var provisionalTail: ASRRecognitionUtterance?
    private var lastRevision = 0
    private var committedThroughTimeMS: Double = -1

    mutating func apply(_ snapshot: ASRRecognitionSnapshot) -> [ASRFinalResult] {
        guard snapshot.revision > lastRevision else { return [] }
        lastRevision = snapshot.revision

        let utterances = snapshot.utterances.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !utterances.isEmpty else {
            provisionalTail = nil
            return []
        }

        let stablePrefix = utterances.dropLast()
        var commits: [ASRFinalResult] = []

        for utterance in stablePrefix where utterance.definite && utterance.endTimeMs > committedThroughTimeMS {
            commits.append(
                ASRFinalResult(
                    text: utterance.text,
                    startTime: utterance.startTimeMs,
                    endTime: utterance.endTimeMs
                )
            )
            committedThroughTimeMS = utterance.endTimeMs
        }

        provisionalTail = utterances.last
        return commits
    }

    mutating func flushRemainingTail() -> ASRFinalResult? {
        guard let provisionalTail else { return nil }
        self.provisionalTail = nil

        guard provisionalTail.endTimeMs > committedThroughTimeMS else {
            return nil
        }

        committedThroughTimeMS = provisionalTail.endTimeMs
        return ASRFinalResult(
            text: provisionalTail.text,
            startTime: provisionalTail.startTimeMs,
            endTime: provisionalTail.endTimeMs
        )
    }
}
