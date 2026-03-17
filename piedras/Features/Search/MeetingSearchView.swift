import SwiftUI

struct MeetingSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(MeetingStore.self) private var meetingStore

    @State private var query = ""

    var body: some View {
        ZStack {
            AppTheme.pageGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Search")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("Find meetings by title, notes, summary or transcript.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
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
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.border.opacity(0.65), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Start typing to filter your meetings." : "No meeting matched that search.")
            .font(.body)
            .foregroundStyle(AppTheme.mutedInk)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
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
