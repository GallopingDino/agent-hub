import SwiftUI

struct PanelView: View {
    private static let maxListHeight: CGFloat = 560

    @ObservedObject var model: PanelModel
    @State private var isStaleExpanded = false
    @State private var listHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model)
            Divider()
            ScrollView {
                content
                    .padding(.vertical, 8)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ListHeightKey.self, value: geometry.size.height)
                    })
            }
            .frame(height: min(listHeight, Self.maxListHeight))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            Divider()
            PanelFooter(model: model)
        }
        .frame(width: 460)
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
    }

    @ViewBuilder
    private var content: some View {
        if let status = model.status {
            VStack(alignment: .leading, spacing: 10) {
                if status.isAgentTabsAvailable == false {
                    PluginWarning()
                }
                sessionSection("Needs you", status.sessions.filter(\.isNeedingUser))
                sessionSection("Working", status.sessions.filter { $0.state == "working" })
                sessionSection("Idle", status.sessions.filter { $0.state == "idle" })
                staleSection(status.sessions.filter { $0.state == "stale" })
            }
        }
        else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.isRefreshing ? "Reading agents…" : "agent-hub did not answer").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    @ViewBuilder
    private func sessionSection(_ title: String, _ sessions: [PanelSession]) -> some View {
        if sessions.isEmpty == false {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(title: title, count: sessions.count)
                ForEach(sessions) { SessionRow(session: $0, model: model) }
            }
        }
    }

    @ViewBuilder
    private func staleSection(_ sessions: [PanelSession]) -> some View {
        if sessions.isEmpty == false {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isStaleExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isStaleExpanded ? 90 : 0))
                        SectionTitle(title: "Forgotten", count: sessions.count)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)

                if isStaleExpanded {
                    ForEach(sessions) { SessionRow(session: $0, model: model) }
                }
            }
        }
    }
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PanelHeader: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: MenuBarIcon.make(hasAttention: false))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Hub").font(.system(size: 13, weight: .semibold))
                summary.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(model.isRefreshing)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summary: Text {
        guard let status = model.status else { return Text("Starting…") }
        let needing = status.sessions.filter(\.isNeedingUser).count
        let working = status.sessions.filter { $0.state == "working" }.count
        let counts = needing > 0 ? "\(needing) need you · \(working) working" : "Nothing waits for you · \(working) working"
        return Text("\(counts) · updated ") + Text(status.generatedAt, style: .relative) + Text(" ago")
    }
}

private struct SectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }
}

private struct SessionRow: View {
    let session: PanelSession
    @ObservedObject var model: PanelModel
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StateBadge(state: session.state)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    ProjectChip(name: session.projectName)
                    Spacer(minLength: 4)
                    Text(IdleFormatter.format(session.idleSeconds))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let detail = detailText {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(session.isNeedingUser ? 2 : 1)
                }
                if session.reviewFiles.isEmpty == false {
                    Label(fileSummary, systemImage: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? Color.primary.opacity(0.07) : Color.clear))
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
        .onHover { isHovered = $0 }
        .onTapGesture {
            if session.hasTerminalTab {
                model.showAgent(session)
            }
        }
        .help(session.hasTerminalTab ? focusHelp : "No Rider terminal tab found for this session")
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if let unityPid = session.unityPid {
                Button { model.showUnityEditor(pid: unityPid) } label: { Image(systemName: "cube") }
                    .help("Show the \(session.projectName) Unity editor")
            }
            if session.artifactUrl != nil {
                Button { model.openArtifact(session) } label: { Image(systemName: "doc.richtext") }
                    .help("Open the agent's artifact in the browser")
            }
            Button { model.showAgent(session) } label: { Image(systemName: "arrow.up.forward.app") }
                .disabled(session.hasTerminalTab == false)
                .help(focusHelp)
        }
        .buttonStyle(IconButtonStyle())
        .opacity(isHovered || session.isNeedingUser ? 1 : 0.45)
    }

    private var detailText: String? {
        if let waitingFor = session.waitingFor, waitingFor.isEmpty == false {
            return waitingFor.prefix(1).uppercased() + waitingFor.dropFirst()
        }
        return session.lastMessagePreview
    }

    private var fileSummary: String {
        let names = session.reviewFiles.map { ($0 as NSString).lastPathComponent }
        return names.count <= 3 ? names.joined(separator: " · ") : names.prefix(3).joined(separator: " · ") + " +\(names.count - 3)"
    }

    private var focusHelp: String {
        let files = session.reviewFiles.count
        return model.isOpeningEditedFilesOnFocus && files > 0 ? "Show the agent's tab and open \(files) edited files" : "Show the agent's tab in Rider"
    }
}

private struct StateBadge: View {
    let state: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(Circle().fill(color.opacity(0.15)))
    }

    private var symbol: String {
        switch state {
        case "waiting": return "hand.raised.fill"
        case "review": return "checkmark"
        case "working": return "bolt.fill"
        case "stale": return "clock"
        default: return "moon.fill"
        }
    }

    private var color: Color {
        switch state {
        case "waiting": return .orange
        case "review": return .green
        case "working": return .blue
        case "stale": return .red
        default: return .gray
        }
    }
}

private struct ProjectChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(ProjectPalette.color(for: name))
            .background(Capsule().fill(ProjectPalette.color(for: name).opacity(0.14)))
    }
}

private struct PluginWarning: View {
    var body: some View {
        Label("Agent Tabs plugin is not reachable in Rider: focusing and opening files won't work.", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            .padding(.horizontal, 10)
    }
}

private struct PanelFooter: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let clones = model.status?.clones {
                cloneRow("Unity", clones.filter { $0.unityPid != nil }, isClickable: true)
                cloneRow("Free", clones.filter(\.isFree), isClickable: false)
            }
            HStack {
                Toggle(isOn: $model.isOpeningEditedFilesOnFocus) {
                    Text("Open edited files on focus").font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func cloneRow(_ title: String, _ clones: [PanelClone], isClickable: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            if clones.isEmpty {
                Text("—").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            else {
                FlowLayout(spacing: 4) {
                    ForEach(clones) { clone in
                        if isClickable, let pid = clone.unityPid {
                            Button { model.showUnityEditor(pid: pid) } label: { ProjectChip(name: clone.name) }
                                .buttonStyle(.plain)
                                .help("Show the \(clone.name) Unity editor")
                        }
                        else {
                            ProjectChip(name: clone.name)
                        }
                    }
                }
            }
        }
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.09 : 0)))
                .onHover { isHovered = $0 }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeRows(subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrangeRows(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrangeRows(_ subviews: Subviews, maxWidth: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > maxWidth, current.indices.isEmpty == false {
                rows.append(current)
                current = ([index], size.width, size.height)
            }
            else {
                current = (current.indices + [index], nextWidth, max(current.height, size.height))
            }
        }
        if current.indices.isEmpty == false {
            rows.append(current)
        }
        return rows
    }
}

enum ProjectPalette {
    private static let hues: [Double] = [0.58, 0.08, 0.36, 0.78, 0.97, 0.47, 0.14, 0.68, 0.25, 0.88, 0.52]
    private static let hueByProject: [String: Double] = [
        "AWay": 0.58, "BaseRun": 0.36, "TowerKing": 0.08, "SpaceInc": 0.78, "Cafe": 0.97,
        "RaceMith": 0.47, "Zuma": 0.14, "Kingdom": 0.68, "GalaxyGuardians": 0.88, "DiggyDogPuzzle": 0.25,
    ]

    // Parallel clones share their main project's colour.
    static func color(for cloneName: String) -> Color {
        let project = cloneName.replacingOccurrences(of: "-parallel", with: "")
        return Color(hue: hueByProject[project] ?? hashedHue(project), saturation: 0.6, brightness: 0.8)
    }

    private static func hashedHue(_ project: String) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in project.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hues[Int(hash % UInt64(hues.count))]
    }
}

enum IdleFormatter {
    static func format(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
