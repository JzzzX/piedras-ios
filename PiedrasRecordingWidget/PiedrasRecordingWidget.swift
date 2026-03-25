import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: RecordingLiveActivityPhase
        var durationSeconds: Int
        var timerStartDate: Date?
    }

    var meetingID: String
}

@main
struct PiedrasRecordingWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivityWidget()
    }
}

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingLiveActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Color(red: 0.95, green: 0.92, blue: 0.88))
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: iconName(for: context.state.phase))
                        .font(.system(size: 20, weight: .bold))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: context.state.phase))
                            .font(.system(size: 15, weight: .semibold))
                        durationText(for: context.state)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.state.phase))
            } compactTrailing: {
                compactDurationText(for: context.state)
            } minimal: {
                Image(systemName: iconName(for: context.state.phase))
            }
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<RecordingLiveActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.84, green: 0.76, blue: 0.67))
                    .frame(width: 44, height: 44)

                Image(systemName: iconName(for: context.state.phase))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: context.state.phase))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)

                durationText(for: context.state)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func durationText(for state: RecordingLiveActivityAttributes.ContentState) -> some View {
        switch RecordingLiveActivityDurationPresenter.display(
            for: state.phase,
            durationSeconds: state.durationSeconds,
            timerStartDate: state.timerStartDate
        ) {
        case .liveTimer(let startDate):
            Text(timerInterval: startDate ... Date(), countsDown: false)
                .monospacedDigit()
        case .staticText(let text):
            Text(text)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func compactDurationText(for state: RecordingLiveActivityAttributes.ContentState) -> some View {
        switch RecordingLiveActivityDurationPresenter.display(
            for: state.phase,
            durationSeconds: state.durationSeconds,
            timerStartDate: state.timerStartDate
        ) {
        case .liveTimer(let startDate):
            Text(timerInterval: startDate ... Date(), countsDown: false)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        case .staticText(let text):
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
    }

    private func iconName(for phase: RecordingLiveActivityPhase) -> String {
        switch phase {
        case .recording:
            return "mic.fill"
        case .paused:
            return "pause.fill"
        }
    }

    private func title(for phase: RecordingLiveActivityPhase) -> String {
        switch phase {
        case .recording:
            return "Piedras 正在录音"
        case .paused:
            return "Piedras 录音已暂停"
        }
    }
}
