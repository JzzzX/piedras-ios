import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settingsStore = settingsStore

        Form {
            Section("后端") {
                TextField("Backend Base URL", text: $settingsStore.backendBaseURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                LabeledContent("可达状态", value: settingsStore.apiReachable ? "可达" : "未检查")
                LabeledContent("ASR", value: settingsStore.asrReady ? "可用" : "未检查")
            }

            Section("隐藏工作区") {
                LabeledContent("Workspace ID", value: settingsStore.hiddenWorkspaceID ?? "尚未初始化")
                LabeledContent("Bootstrap", value: settingsStore.workspaceBootstrapState.rawValue)
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
}
