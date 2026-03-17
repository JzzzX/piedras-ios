import SwiftUI

private struct MeetingDaySection: Identifiable {
    let id: String
    let title: String
    let meetings: [Meeting]
}

struct MeetingListView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(AppRouter.self) private var router
    @Environment(RecordingSessionStore.self) private var recordingSessionStore

    var body: some View {
        ZStack {
            AppTheme.pageGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if let activeMeeting = meetingStore.activeRecordingMeeting {
                        activeRecordingCard(meeting: activeMeeting)
                    }

                    if groupedMeetings.isEmpty {
                        emptyState
                    } else {
                        meetingSections
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 132)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            bottomDock
        }
        .overlay(alignment: .top) {
            if let error = meetingStore.lastErrorMessage {
                errorBanner(error)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .textCase(.uppercase)

                Text("Notes")
                    .font(.system(size: 46, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("Keep the conversation, lose the clutter.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            HStack(spacing: 10) {
                headerButton(systemName: "magnifyingglass") {
                    router.showSearch()
                }

                headerButton(systemName: "slider.horizontal.3") {
                    router.showSettings()
                }
            }
        }
    }

    private func activeRecordingCard(meeting: Meeting) -> some View {
        Button {
            router.showMeeting(id: meeting.id)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(AppTheme.highlight)
                        .frame(width: 10, height: 10)

                    Text("Recording now")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .textCase(.uppercase)

                    Spacer()

                    Text(recordingSessionStore.durationSeconds.mmss)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text(meeting.displayTitle)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(activeRecordingPreview)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    statusChip(title: recordingSessionStore.phase.displayLabel, tint: AppTheme.highlightSoft, foreground: AppTheme.ink)
                    statusChip(title: recordingSessionStore.asrState.displayLabel, tint: .white.opacity(0.16), foreground: .white.opacity(0.9))
                }
            }
            .padding(20)
            .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 18, x: 0, y: 14)
        }
        .buttonStyle(.plain)
    }

    private var meetingSections: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(groupedMeetings) { section in
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.ink)

                    VStack(spacing: 14) {
                        ForEach(section.meetings) { meeting in
                            MeetingRowView(
                                meeting: meeting,
                                isRecording: meeting.id == recordingSessionStore.meetingID && recordingSessionStore.phase != .idle,
                                onOpen: {
                                    router.showMeeting(id: meeting.id)
                                },
                                onDelete: {
                                    meetingStore.deleteMeeting(id: meeting.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your first note starts here.")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.ink)

            Text("Tap record to capture a conversation. Transcript, notes and AI summary will build around that recording automatically.")
                .font(.body)
                .foregroundStyle(AppTheme.mutedInk)

            HStack(spacing: 10) {
                Label("16kHz mic capture", systemImage: "mic.fill")
                Label("Live transcript", systemImage: "waveform")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.subtleInk)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
        }
    }

    private var bottomDock: some View {
        HStack(spacing: 12) {
            Button {
                router.showGlobalChat()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                    Text("Ask anything")
                        .font(.headline)
                    Spacer()
                }
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 18)
                .frame(height: 58)
                .background(AppTheme.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Button {
                if recordingSessionStore.phase == .idle {
                    guard let meeting = meetingStore.createMeeting() else { return }
                    router.showMeeting(id: meeting.id)
                    Task {
                        await meetingStore.startRecording(meetingID: meeting.id)
                    }
                } else {
                    Task {
                        await meetingStore.stopRecording()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(recordingSessionStore.phase == .idle ? AppTheme.ink : AppTheme.highlight)

                    Image(systemName: recordingSessionStore.phase == .idle ? "mic.fill" : "stop.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                .shadow(color: AppTheme.cardShadow, radius: 14, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recordingSessionStore.phase == .idle ? "新录音" : "停止")
            .accessibilityIdentifier("NewRecordingButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
                .background(AppTheme.surface.opacity(0.92), in: Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func statusChip(title: String, tint: Color, foreground: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                meetingStore.clearLastError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.82))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.danger, in: Capsule())
        .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 8)
    }

    private var groupedMeetings: [MeetingDaySection] {
        let grouped = Dictionary(grouping: meetingStore.meetings) { meeting in
            Calendar.current.startOfDay(for: meeting.date)
        }

        return grouped
            .keys
            .sorted(by: >)
            .map { day in
                let meetings = (grouped[day] ?? []).sorted(by: { $0.updatedAt > $1.updatedAt })
                return MeetingDaySection(
                    id: day.ISO8601Format(),
                    title: meetings.first?.daySectionTitle ?? day.formatted(.dateTime.month(.wide).day()),
                    meetings: meetings
                )
            }
    }

    private var activeRecordingPreview: String {
        if !recordingSessionStore.currentPartial.isEmpty {
            return recordingSessionStore.currentPartial
        }

        if let info = recordingSessionStore.infoBanner, !info.isEmpty {
            return info
        }

        return "Live transcription is attached to this note while recording continues."
    }
}
