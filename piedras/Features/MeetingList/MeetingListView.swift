import SwiftUI
import UniformTypeIdentifiers

private enum MeetingHomeBucket: String, CaseIterable, Identifiable {
    case processing = "Processing"
    case today = "Today"
    case yesterday = "Yesterday"
    case earlierThisWeek = "Earlier this week"
    case earlier = "Earlier"

    var id: String { rawValue }

    var title: String {
        let s = AppStrings.current
        switch self {
        case .processing: return s.bucketProcessing
        case .today: return s.bucketToday
        case .yesterday: return s.bucketYesterday
        case .earlierThisWeek: return s.bucketEarlierThisWeek
        case .earlier: return s.bucketEarlier
        }
    }
}

private struct MeetingHomeSectionSnapshot: Identifiable {
    let bucket: MeetingHomeBucket
    let rows: [MeetingRowSnapshot]

    var id: String { bucket.id }
    var title: String { bucket.title }
}

struct MeetingListView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(AppRouter.self) private var router
    @Environment(RecordingSessionStore.self) private var recordingSessionStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var isImportingSourceAudio = false

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            VStack(spacing: 14) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                feedList
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
                    .padding(.horizontal, 16)
            }
        }
        .fileImporter(
            isPresented: $isImportingSourceAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleSourceAudioSelection(result)
        }
        .id(settingsStore.appLanguage)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(AppStrings.current.appTitle)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            HStack(spacing: 8) {
                headerToolButton(
                    systemName: "magnifyingglass",
                    accessibilityLabel: AppStrings.current.search,
                    identifier: "HomeSearchButton"
                ) {
                    router.showSearch()
                }

                headerToolButton(
                    systemName: "slider.horizontal.3",
                    accessibilityLabel: AppStrings.current.settings,
                    identifier: "HomeSettingsButton"
                ) {
                    router.showSettings()
                }
            }
        }
    }

    private var feedList: some View {
        List {
            if homeSections.isEmpty {
                Section {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(homeSections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            MeetingRowView(
                                snapshot: row,
                                onOpen: {
                                    router.showMeeting(id: row.id)
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(AppStrings.current.deleteAction, role: .destructive) {
                                    meetingStore.deleteMeeting(id: row.id)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(section.title.uppercased())
                            .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.subtleInk)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .id(feedStructureIdentity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            RetroIconBadge(systemName: "mic.fill", size: 48, symbolSize: 17)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.current.noNotesYet)
                    .font(AppTheme.bodyFont(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                Text(AppStrings.current.tapMicToCapture)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: AppTheme.subtleBorderWidth, dash: [8, 4]))
                .foregroundStyle(AppTheme.subtleBorderColor)
        )
    }

    private var bottomDock: some View {
        VStack(spacing: 0) {
            // 向上渐变 scrim — 让滚动内容柔和淡出
            LinearGradient(
                colors: [
                    AppTheme.background.opacity(0),
                    AppTheme.background.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            unifiedBottomDock
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var unifiedBottomDock: some View {
        HStack(spacing: 14) {
            dockIconButton(
                systemName: "waveform.badge.plus",
                accessibilityLabel: "上传音频",
                identifier: "HomeUploadAudioButton",
                action: openUploadAudio
            )

            Rectangle()
                .fill(AppTheme.subtleBorderColor)
                .frame(width: AppTheme.subtleBorderWidth, height: 28)

            recordingButton(size: 58)

            Rectangle()
                .fill(AppTheme.subtleBorderColor)
                .frame(width: AppTheme.subtleBorderWidth, height: 28)

            homeChatLauncher
        }
        .padding(.horizontal, 16)
        .frame(height: 74)
        .background(
            Rectangle()
                .fill(AppTheme.dockSurface)
                .shadow(color: AppTheme.border.opacity(0.08), radius: 10, x: 0, y: 3)
        )
        .overlay(
            Rectangle()
                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
        )
    }

    private var homeChatLauncher: some View {
        Button(action: openGlobalChat) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.subtleInk)

                Text(AppStrings.current.chatWithNotes)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.subtleInk)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.current.chatWithNotes)
        .accessibilityIdentifier("HomeGlobalChatLauncher")
    }

    private func dockIconButton(
        systemName: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private func recordingButton(size: CGFloat) -> some View {
        Button {
            hideKeyboard()

            if recordingSessionStore.phase == .idle {
                startMicrophoneRecording()
            } else {
                Task {
                    await meetingStore.stopRecording()
                }
            }
        } label: {
            ZStack {
                Rectangle()
                    .fill(recordingSessionStore.phase == .idle ? AppTheme.surface : AppTheme.highlight)

                Image(systemName: recordingSessionStore.phase == .idle ? "mic.fill" : "stop.fill")
                    .font(.system(size: size * 0.30, weight: .bold))
                    .foregroundStyle(recordingSessionStore.phase == .idle ? AppTheme.ink : .white)
            }
            .frame(width: size, height: size)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.ink, lineWidth: 2)
            )
            .retroHardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recordingSessionStore.phase == .idle ? AppStrings.current.newRecording : AppStrings.current.stop)
        .accessibilityIdentifier("NewRecordingButton")
    }

    private func headerToolButton(
        systemName: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.mutedInk)
                .frame(width: 40, height: 40)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
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
        .background(AppTheme.danger)
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
        .retroHardShadow()
        .accessibilityIdentifier("HomeErrorBanner")
    }

    // MARK: - Data

    private var homeSections: [MeetingHomeSectionSnapshot] {
        let calendar = Calendar.current
        var grouped: [MeetingHomeBucket: [Meeting]] = [:]

        for meeting in meetingStore.meetings {
            let bucket = sectionBucket(for: meeting, calendar: calendar)
            grouped[bucket, default: []].append(meeting)
        }

        return MeetingHomeBucket.allCases.compactMap { bucket in
            guard let meetings = grouped[bucket], !meetings.isEmpty else {
                return nil
            }

            return MeetingHomeSectionSnapshot(
                bucket: bucket,
                rows: meetings
                    .sorted(by: { $0.updatedAt > $1.updatedAt })
                    .map { MeetingRowSnapshot(meeting: $0, isRecording: isMeetingRecording($0)) }
            )
        }
    }

    private var feedStructureIdentity: String {
        homeSections
            .map { section in
                let rowIDs = section.rows.map(\.id).joined(separator: ",")
                return "\(section.id):\(rowIDs)"
            }
            .joined(separator: "|")
    }

    private func sectionBucket(for meeting: Meeting, calendar: Calendar) -> MeetingHomeBucket {
        if isMeetingProcessing(meeting) {
            return .processing
        }

        if calendar.isDateInToday(meeting.date) {
            return .today
        }

        if calendar.isDateInYesterday(meeting.date) {
            return .yesterday
        }

        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: .now),
           weekInterval.contains(meeting.date) {
            return .earlierThisWeek
        }

        return .earlier
    }

    private func isMeetingProcessing(_ meeting: Meeting) -> Bool {
        if isMeetingRecording(meeting) {
            return true
        }

        if meetingStore.isFileTranscribing(meetingID: meeting.id) {
            return true
        }

        if meetingStore.isGeneratingTitle(meetingID: meeting.id) {
            return true
        }

        if meetingStore.isEnhancing(meetingID: meeting.id) {
            return true
        }

        return meeting.syncState == .syncing
    }

    private func isMeetingRecording(_ meeting: Meeting) -> Bool {
        meeting.id == recordingSessionStore.meetingID && recordingSessionStore.phase != .idle
    }

    private func openUploadAudio() {
        isImportingSourceAudio = true
    }

    private func openGlobalChat() {
        router.showGlobalChat()
    }

    private func startMicrophoneRecording() {
        guard let meeting = meetingStore.createMeeting(startingRecording: true) else { return }
        router.showMeeting(id: meeting.id)
        Task {
            await meetingStore.startRecording(meetingID: meeting.id)
        }
    }

    private func handleSourceAudioSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let sourceURL = urls.first else { return }
            guard let meeting = meetingStore.createMeeting() else { return }
            router.showMeeting(id: meeting.id)
            let displayName = sourceURL.deletingPathExtension().lastPathComponent
            Task {
                await meetingStore.startFileTranscription(
                    meetingID: meeting.id,
                    sourceAudio: SourceAudioAsset(
                        fileURL: sourceURL,
                        displayName: displayName
                    )
                )
            }
        case let .failure(error):
            meetingStore.lastErrorMessage = error.localizedDescription
        }
    }
}
