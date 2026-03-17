import SwiftUI

struct MeetingSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore

    @State private var query = ""

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
                                    meeting: meeting,
                                    isRecording: false,
                                    onOpen: {
                                        openMeeting(meeting.id)
                                    },
                                    onDelete: {
                                        meetingStore.deleteMeeting(id: meeting.id)
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
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Search")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("Notes")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            AppGlassCircleButton(systemName: "xmark", accessibilityLabel: "关闭") {
                dismiss()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.subtleInk)

            TextField("Search notes and transcript", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.ink)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.subtleInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background {
            AppGlassSurface(cornerRadius: 22, style: .regular, shadowOpacity: 0.05)
        }
    }

    private var emptyState: some View {
        AppGlassCard(cornerRadius: 30, style: .regular, padding: 20, shadowOpacity: 0.06) {
            HStack(spacing: 10) {
                Image(systemName: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "magnifyingglass" : "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.subtleInk)

                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Start typing." : "No match.")
                    .font(.body)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }

    private var searchResults: [Meeting] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(meetingStore.meetings.prefix(12))
        }

        return meetingStore.searchMeetings(matching: query)
    }

    private func openMeeting(_ meetingID: String) {
        dismiss()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            router.showMeeting(id: meetingID)
        }
    }
}
