import SwiftUI

struct MeetingSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchField

                    if searchResults.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 14) {
                            ForEach(searchResults) { meeting in
                                MeetingRowView(
                                    snapshot: MeetingRowSnapshot(meeting: meeting, isRecording: false),
                                    onOpen: {
                                        openMeeting(meeting.id)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap(isFocused: $isSearchFocused)
        .toolbar(.hidden, for: .navigationBar)
        .id(settingsStore.appLanguage)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.current.search)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)

                Text(AppStrings.current.notes)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            AppGlassCircleButton(systemName: "xmark", accessibilityLabel: AppStrings.current.close) {
                dismiss()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.subtleInk)

            TextField(AppStrings.current.searchNotesAndTranscript, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .focused($isSearchFocused)

            if !query.isEmpty {
                Button {
                    isSearchFocused = false
                    hideKeyboard()
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 24, height: 24)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "magnifyingglass" : "doc.text.magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.subtleInk)

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppStrings.current.startTyping : AppStrings.current.noMatch)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
    }

    private var searchResults: [Meeting] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(meetingStore.meetings.prefix(12))
        }

        return meetingStore.searchMeetings(matching: query)
    }

    private func openMeeting(_ meetingID: String) {
        isSearchFocused = false
        hideKeyboard()
        dismiss()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            router.showMeeting(id: meetingID)
        }
    }
}
