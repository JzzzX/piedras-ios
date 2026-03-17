import Foundation
import SwiftData

enum ModelContainerFactory {
    @MainActor
    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([
            Meeting.self,
            TranscriptSegment.self,
            ChatMessage.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
