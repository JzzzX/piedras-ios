import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    let text: String
    let meetingID: String

    var body: some View {
        Group {
            if meetingStore.isEnhancing(meetingID: meetingID) {
                processingState
            } else {
                MarkdownDocumentView(
                    markdown: text,
                    placeholder: AppStrings.current.noAINotesYet,
                    minHeight: 420,
                    accessibilityIdentifier: "EnhancedNotesRenderedView"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id(settingsStore.appLanguage)
    }

    private var processingState: some View {
        VStack(spacing: 0) {
            RetroTitleBar(label: AppStrings.current.processing)

            VStack(spacing: 16) {
                RetroCheckerboardProgress(progress: 0.65)

                HStack(spacing: 4) {
                    Text(AppStrings.current.generatingNotesShort)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)

                    RetroBlinkingCursor()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
    }
}
