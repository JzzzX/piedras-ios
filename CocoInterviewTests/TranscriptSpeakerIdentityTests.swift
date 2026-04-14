import Foundation
import Testing
@testable import CocoInterview

struct TranscriptSpeakerIdentityTests {
    @Test
    func displayNameUsesNumericFallbackForGeneratedSpeakers() {
        let previousLanguage = AppStrings.currentLanguage
        AppStrings.syncLanguage(.chinese)
        defer { AppStrings.syncLanguage(previousLanguage) }

        let meeting = Meeting()

        #expect(meeting.displayName(forSpeaker: "spk_1") == "说话人 1")
        #expect(meeting.displayName(forSpeaker: "spk_27") == "说话人 27")
    }

    @Test
    func resolverKeepsStableAvatarTokenForLegacySpeakerKeys() {
        let english = AppStringTable(language: .english)

        let alpha = TranscriptSpeakerIdentity.resolve(
            speakerKey: "Speaker A",
            displayName: nil,
            strings: english
        )
        #expect(alpha.avatarToken == "A")
        #expect(alpha.paletteIndex == 0)

        let numeric = TranscriptSpeakerIdentity.resolve(
            speakerKey: "Speaker 2",
            displayName: nil,
            strings: english
        )
        #expect(numeric.avatarToken == "B")
        #expect(numeric.paletteIndex == 1)
    }

    @Test
    func resolverKeepsAvatarTokenStableWhenSpeakerIsRenamed() {
        let chinese = AppStringTable(language: .chinese)

        let identity = TranscriptSpeakerIdentity.resolve(
            speakerKey: "spk_2",
            displayName: "张总",
            strings: chinese
        )

        #expect(identity.avatarToken == "B")
        #expect(identity.title == "张总")
        #expect(identity.defaultTitle == "说话人 2")
    }
}
