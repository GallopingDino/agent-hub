import SwiftUI

// The usage block at the top of the settings menu: one aligned row per agent, used share of each window and when it resets.
struct UsageMenuView: View {
    static let nearLimitColor = Color(red: 1, green: 0.42, blue: 0.36)

    let usage: [PanelAgentUsage]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 5) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                columnTitle("5 hours")
                columnTitle("Week")
            }
            ForEach(usage, id: \.agent) { agentUsage in
                GridRow {
                    Text(agentUsage.agentName)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 16)
                    if let error = agentUsage.error {
                        Text(error)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .gridCellColumns(2)
                    }
                    else {
                        windowCell(agentUsage.fiveHour, placeholder: "asleep")
                        windowCell(agentUsage.weekly, placeholder: "unknown")
                    }
                }
            }
        }
        .font(.system(size: 13))
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .fixedSize()
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func windowCell(_ window: PanelUsageWindow?, placeholder: String) -> some View {
        if let window {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(window.usedPercent)%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(window.isNearLimit ? Self.nearLimitColor : .primary)
                    .frame(minWidth: 34, alignment: .trailing)
                Text(UsageResetFormatter.format(window.resetsAt))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.trailing, 18)
        }
        else {
            Text(placeholder)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 18)
        }
    }
}

enum UsageResetFormatter {
    private static let dayLength: TimeInterval = 24 * 3600

    // Within a day the clock time says it best, further out the weekday does.
    static func format(_ date: Date) -> String {
        if date.timeIntervalSinceNow < dayLength {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
