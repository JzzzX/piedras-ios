import SwiftUI

struct MeetingTypePickerCard: View {
    let selectedType: MeetingTypeOption
    let onSelect: (MeetingTypeOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(MeetingTypeOption.allCases.enumerated()), id: \.element.id) { index, type in
                Button {
                    onSelect(type)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: type == selectedType ? "checkmark" : "circle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(type == selectedType ? AppTheme.ink : AppTheme.subtleInk.opacity(0.55))
                            .frame(width: 16)

                        Text(AppStrings.current.meetingTypeName(type))
                            .font(AppTheme.bodyFont(size: 16, weight: type == selectedType ? .bold : .semibold))
                            .foregroundStyle(AppTheme.ink)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("MeetingTypeOption_\(type.rawValue)")

                if index < MeetingTypeOption.allCases.count - 1 {
                    ThinDivider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 248, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
        )
        .retroHardShadow(x: 0, y: 10, color: Color.black.opacity(0.10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MeetingTypeOverlay")
    }
}
