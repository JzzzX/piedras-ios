import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        @Bindable var settingsStore = settingsStore

        Form {
            Section("后端") {
                TextField("Backend Base URL", text: $settingsStore.backendBaseURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                Button(settingsStore.isCheckingHealth ? "检查中..." : "检查连接") {
                    Task {
                        await meetingStore.checkBackendHealth(force: true)
                    }
                }
                .disabled(settingsStore.isCheckingHealth)

                LabeledContent("可达状态", value: backendStateLabel)
                Text(settingsStore.backendStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("ASR", value: settingsStore.asrReady ? "可用" : "不可用")
                Text(settingsStore.asrStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("隐藏工作区") {
                LabeledContent("Workspace ID", value: settingsStore.hiddenWorkspaceID ?? "尚未初始化")
                LabeledContent("Bootstrap", value: workspaceBootstrapLabel)
                Button(settingsStore.workspaceBootstrapState == .loading ? "初始化中..." : "初始化工作区") {
                    Task {
                        await meetingStore.bootstrapHiddenWorkspace(force: true)
                    }
                }
                .disabled(settingsStore.workspaceBootstrapState == .loading)

                Text(settingsStore.workspaceStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("同步") {
                Button(settingsStore.isSyncing ? "同步中..." : "立即同步") {
                    Task {
                        await meetingStore.syncAllMeetings()
                    }
                }
                .disabled(settingsStore.isSyncing)

                if !settingsStore.syncStatusMessage.isEmpty {
                    Text(settingsStore.syncStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("MVP 边界") {
                Text("当前阶段只保留录音、转写、纯文本笔记和单会议 AI。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var backendStateLabel: String {
        if settingsStore.lastHealthCheckAt == nil {
            return "未检查"
        }

        return settingsStore.apiReachable ? "可达" : "不可达"
    }

    private var workspaceBootstrapLabel: String {
        switch settingsStore.workspaceBootstrapState {
        case .idle:
            return "未开始"
        case .loading:
            return "初始化中"
        case .success:
            return "已完成"
        case .failed:
            return "失败"
        }
    }
}
