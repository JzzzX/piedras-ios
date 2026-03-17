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
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let activeMeeting = meetingStore.activeRecordingMeeting {
                        activeRecordingStrip(meeting: activeMeeting)
                    }

                    if groupedMeetings.isEmpty {
                        emptyState
                    } else {
                        meetingSections
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 140)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.subtleInk)
                    .textCase(.uppercase)

                Text("Notes")
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)
            }

            Spacer()

            HStack(spacing: 10) {
                AppGlassCircleButton(systemName: "magnifyingglass", accessibilityLabel: "搜索") {
                    router.showSearch()
                }

                AppGlassCircleButton(systemName: "slider.horizontal.3", accessibilityLabel: "设置") {
                    router.showSettings()
                }
            }
        }
    }

    private func activeRecordingStrip(meeting: Meeting) -> some View {
        Button {
            router.showMeeting(id: meeting.id)
        } label: {
            AppGlassCard(cornerRadius: 32, style: .regular, padding: 18, shadowOpacity: 0.10) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            AppGlassSurface(cornerRadius: 20, style: .clear, shadowOpacity: 0.04)
                                .frame(width: 48, height: 48)

                            Image(systemName: "doc.text")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(AppTheme.highlight)
                                    .frame(width: 8, height: 8)

                                Text(meeting.displayTitle)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                            }

                            if !activeRecordingPreview.isEmpty {
                                Text(activeRecordingPreview)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        Text(recordingSessionStore.durationSeconds.mmss)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }

                    WaveformView(samples: recordingSessionStore.waveformSamples)
                        .frame(height: 28)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var meetingSections: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(groupedMeetings) { section in
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedInk)

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
        AppGlassCard(cornerRadius: 34, style: .regular, padding: 22, shadowOpacity: 0.08) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    AppGlassSurface(cornerRadius: 24, style: .clear, shadowOpacity: 0.03)
                        .frame(width: 62, height: 62)

                    Image(systemName: "doc.text")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("No notes")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.ink)

                    Text("Tap the mic.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtleInk)
                }
            }
        }
    }

    private var bottomDock: some View {
        HStack {
            Spacer()

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
                    if recordingSessionStore.phase == .idle {
                        AppGlassSurface(cornerRadius: 34, style: .regular, borderOpacity: 0.30, shadowOpacity: 0.14)
                    } else {
                        Circle()
                            .fill(AppTheme.highlight)
                            .shadow(color: AppTheme.highlight.opacity(0.30), radius: 20, x: 0, y: 10)
                    }

                    Image(systemName: recordingSessionStore.phase == .idle ? "mic.fill" : "stop.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(recordingSessionStore.phase == .idle ? AppTheme.ink : .white)
                }
                .frame(width: 68, height: 68)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recordingSessionStore.phase == .idle ? "新录音" : "停止")
            .accessibilityIdentifier("NewRecordingButton")

            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(Color.clear)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                meetingStore.clearLastError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.84))
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

        return ""
    }
}
