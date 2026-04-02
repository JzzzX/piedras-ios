import Foundation
import Testing
@testable import piedras

struct TranscriptSpeakerIdentityTests {
    @Test
    func displayNameUsesAlphabeticFallbackForGeneratedSpeakers() {
        let previousLanguage = AppStrings.currentLanguage
        AppStrings.syncLanguage(.chinese)
        defer { AppStrings.syncLanguage(previousLanguage) }

        let meeting = Meeting()

        #expect(meeting.displayName(forSpeaker: "spk_1") == "发言人 A")
        #expect(meeting.displayName(forSpeaker: "spk_27") == "发言人 AA")
    }

    @Test
    func resolverUnderstandsLegacySpeakerKeys() {
        let english = AppStringTable(language: .english)

        let alpha = TranscriptSpeakerIdentity.resolve(
            speakerKey: "Speaker A",
            displayName: nil,
            strings: english
        )
        #expect(alpha.avatarToken == "A")
        #expect(alpha.title == "Speaker A")
        #expect(alpha.defaultTitle == "Speaker A")

        let numeric = TranscriptSpeakerIdentity.resolve(
            speakerKey: "Speaker 2",
            displayName: nil,
            strings: english
        )
        #expect(numeric.avatarToken == "B")
        #expect(numeric.title == "Speaker B")
        #expect(numeric.defaultTitle == "Speaker B")
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
        #expect(identity.defaultTitle == "发言人 B")
    }
}
