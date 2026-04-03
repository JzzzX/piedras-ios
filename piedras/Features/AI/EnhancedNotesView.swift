import SwiftUI

struct EnhancedNotesView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    let text: String
    let meetingID: String
    let forceProcessingState: Bool

    var body: some View {
        Group {
            if forceProcessingState || (meetingStore.isEnhancing(meetingID: meetingID) && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                processingState
            } else {
                MarkdownDocumentView(
                    markdown: text,
                    placeholder: AppStrings.current.noAINotesYet,
                    minHeight: 420,
                    bodyLineSpacing: 8,
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
                        .font(AppTheme.bodyFont(size: 14))
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
