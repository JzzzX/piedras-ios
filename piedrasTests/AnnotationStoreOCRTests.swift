import Foundation
import SwiftData
import Testing
import UIKit
@testable import piedras

private struct MockAnnotationImageTextExtractor: AnnotationImageTextExtracting {
    let extractedText: String

    func extractText(from imageURLs: [URL]) async throws -> String {
        #expect(!imageURLs.isEmpty)
        return extractedText
    }
}

struct AnnotationStoreOCRTests {
    @MainActor
    @Test
    func addingImageExtractsTextAndMarksMeetingPendingRefresh() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let annotationRepository = AnnotationRepository(modelContext: container.mainContext)
        let store = AnnotationStore(
            repository: annotationRepository,
            imageTextExtractor: MockAnnotationImageTextExtractor(
                extractedText: "白板写着：4 月 8 日开始灰度。"
            )
        )

        let meeting = Meeting(
            title: "图片 OCR 测试",
            enhancedNotes: "现有 AI 笔记"
        )
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "我们看看白板上的时间。",
            startTime: 12_000,
            endTime: 18_000,
            orderIndex: 0
        )
        segment.meeting = meeting
        meeting.segments = [segment]
        container.mainContext.insert(meeting)
        try container.mainContext.save()
        defer { AnnotationImageStorage.deleteAllAnnotations(meetingID: meeting.id) }

        store.addImage(makeTestImage(), to: segment, meetingID: meeting.id)

        let annotation = try await waitForAnnotation(on: segment)
        #expect(annotation.imageTextStatus == .ready)
        #expect(annotation.imageTextContext.contains("4 月 8 日开始灰度"))
        #expect(meeting.aiNotesFreshnessState == .staleFromAttachments)
    }

    @MainActor
    @Test
    func backfillImageTextProcessesExistingAnnotationsMissingOCR() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let annotationRepository = AnnotationRepository(modelContext: container.mainContext)
        let store = AnnotationStore(
            repository: annotationRepository,
            imageTextExtractor: MockAnnotationImageTextExtractor(
                extractedText: "投影写着：灰度范围仅限内测用户。"
            )
        )

        let meeting = Meeting(title: "历史图片补录")
        let segment = TranscriptSegment(
            speaker: "Speaker A",
            text: "先看投影里的范围。",
            startTime: 8_000,
            endTime: 12_000,
            orderIndex: 0
        )
        let annotation = SegmentAnnotation()
        annotation.segment = segment
        segment.annotation = annotation
        segment.meeting = meeting
        meeting.segments = [segment]
        container.mainContext.insert(meeting)
        container.mainContext.insert(annotation)
        try container.mainContext.save()
        defer { AnnotationImageStorage.deleteAllAnnotations(meetingID: meeting.id) }

        let fileName = try AnnotationImageStorage.saveImage(
            makeTestImage(),
            meetingID: meeting.id,
            annotationID: annotation.id
        )
        annotationRepository.addImageFileName(fileName, to: annotation)
        try annotationRepository.save()

        await store.backfillImageTextIfNeeded()

        #expect(annotation.imageTextStatus == .ready)
        #expect(annotation.imageTextContext.contains("灰度范围仅限内测用户"))
    }

    @MainActor
    private func waitForAnnotation(
        on segment: TranscriptSegment,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> SegmentAnnotation {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let annotation = segment.annotation, annotation.imageTextStatus == .ready {
                return annotation
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw NSError(domain: "AnnotationStoreOCRTests", code: 1)
    }

    @MainActor
    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            UIColor.black.setStroke()
            context.stroke(CGRect(x: 4, y: 4, width: 32, height: 32))
        }
    }
}
