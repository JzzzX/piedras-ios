import SwiftUI

struct MeetingListView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var meetingStore = meetingStore

        List {
            if meetingStore.meetings.isEmpty {
                ContentUnavailableView(
                    "还没有会议",
                    systemImage: "waveform.and.mic",
                    description: Text("先开始第一场录音，逐步把录音、转写、笔记和 AI 串起来。")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(meetingStore.meetings) { meeting in
                    NavigationLink(value: AppRoute.meeting(meeting.id)) {
                        MeetingRowView(meeting: meeting)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            meetingStore.deleteMeeting(id: meeting.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Piedras")
        .searchable(text: $meetingStore.searchText, prompt: "搜索标题、笔记或转写")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.showSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let meeting = meetingStore.createMeeting() else { return }
                    router.showMeeting(id: meeting.id)
                    Task {
                        await meetingStore.startRecording(meetingID: meeting.id)
                    }
                } label: {
                    Label("新录音", systemImage: "plus.circle.fill")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = meetingStore.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }
}
