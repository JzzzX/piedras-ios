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

private struct MeetingHomeSection: Identifiable {
    let bucket: MeetingHomeBucket
    let meetings: [Meeting]

    var id: String { bucket.id }
    var title: String { bucket.title }
}

struct MeetingListView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(AppRouter.self) private var router
    @Environment(RecordingSessionStore.self) private var recordingSessionStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var homeChatInput = ""
    @State private var isImportingSourceAudio = false
    @FocusState private var isHomeChatFocused: Bool

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
        .dismissKeyboardOnTap(isFocused: $isHomeChatFocused)
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
                AppGlassCircleButton(systemName: "magnifyingglass", accessibilityLabel: "搜索", size: 40) {
                    router.showSearch()
                }
                .accessibilityIdentifier("HomeSearchButton")

                AppGlassCircleButton(systemName: "slider.horizontal.3", accessibilityLabel: "设置", size: 40) {
                    router.showSettings()
                }
                .accessibilityIdentifier("HomeSettingsButton")
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
                        ForEach(section.meetings) { meeting in
                            MeetingRowView(
                                meeting: meeting,
                                isRecording: isMeetingRecording(meeting),
                                onOpen: {
                                    router.showMeeting(id: meeting.id)
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(AppStrings.current.deleteAction, role: .destructive) {
                                    meetingStore.deleteMeeting(id: meeting.id)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(section.title.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
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
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            RetroIconBadge(systemName: "mic.fill", size: 48, symbolSize: 17)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.current.noNotesYet)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)

                Text(AppStrings.current.tapMicToCapture)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundStyle(AppTheme.border)
        )
        .retroHardShadow()
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
                .fill(AppTheme.border)
                .frame(width: AppTheme.retroBorderWidth, height: 28)

            recordingButton(size: 58)

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: AppTheme.retroBorderWidth, height: 28)

            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.subtleInk)

                TextField(AppStrings.current.chatWithNotes, text: $homeChatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .focused($isHomeChatFocused)
                    .submitLabel(.send)
                    .onSubmit(sendHomeQuestion)
                    .accessibilityIdentifier("HomeGlobalChatField")

                if !trimmedHomeChatInput.isEmpty {
                    Button(action: sendHomeQuestion) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.surface)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.ink)
                            .overlay(
                                Rectangle()
                                    .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("HomeGlobalChatSendButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 74)
        .background(
            Rectangle()
                .fill(AppTheme.dockSurface)
                .shadow(color: AppTheme.border.opacity(0.18), radius: 12, x: 0, y: -4)
                .shadow(color: AppTheme.border.opacity(0.18), radius: 12, x: 0, y: 4)
        )
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
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
                if recordingSessionStore.phase == .idle {
                    RetroIconBadge(systemName: "mic.fill", size: size, symbolSize: size * 0.34)
                } else {
                    Rectangle()
                        .fill(AppTheme.highlight)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )

                    Image(systemName: "stop.fill")
                        .font(.system(size: size * 0.30, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recordingSessionStore.phase == .idle ? AppStrings.current.newRecording : AppStrings.current.stop)
        .accessibilityIdentifier("NewRecordingButton")
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
    }

    // MARK: - Data

    private var homeSections: [MeetingHomeSection] {
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

            return MeetingHomeSection(
                bucket: bucket,
                meetings: meetings.sorted(by: { $0.updatedAt > $1.updatedAt })
            )
        }
    }

    private var trimmedHomeChatInput: String {
        homeChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
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
        isHomeChatFocused = false
        hideKeyboard()
        isImportingSourceAudio = true
    }

    private func sendHomeQuestion() {
        let question = trimmedHomeChatInput
        guard !question.isEmpty else { return }

        isHomeChatFocused = false
        hideKeyboard()
        homeChatInput = ""
        router.showGlobalChat(initialQuestion: question)
    }

    private func startMicrophoneRecording() {
        isHomeChatFocused = false
        hideKeyboard()
        guard let meeting = meetingStore.createMeeting() else { return }
        router.showMeeting(id: meeting.id)
        Task {
            await meetingStore.startRecording(meetingID: meeting.id)
        }
    }

    private func handleSourceAudioSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            isHomeChatFocused = false
            hideKeyboard()
            guard let sourceURL = urls.first else { return }
            guard let meeting = meetingStore.createMeeting() else { return }
            router.showMeeting(id: meeting.id)
            let displayName = sourceURL.deletingPathExtension().lastPathComponent
            Task {
                await meetingStore.startRecording(
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
