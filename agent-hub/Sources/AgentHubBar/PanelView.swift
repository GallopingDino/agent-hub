import SwiftUI

struct PanelView: View {
    private static let maxListHeight: CGFloat = 600
    private static let groupSpacing: CGFloat = 10

    @ObservedObject var model: PanelModel
    @State private var listHeight: CGFloat = 120
    @State private var isForgottenExpanded = false
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var drag: GroupDrag?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model)
            if let notice = model.notice {
                NoticeBanner(text: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollView {
                content
                    .padding(10)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ListHeightKey.self, value: geometry.size.height)
                    })
            }
            .frame(height: min(listHeight, Self.maxListHeight))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            if freeClones.isEmpty == false {
                PanelFooter(freeClones: freeClones)
            }
        }
        .frame(width: 480)
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
    }

    private var freeClones: [PanelClone] {
        model.status?.clones.filter { $0.isRunning && $0.isFree } ?? []
    }

    @ViewBuilder
    private var content: some View {
        if let status = model.status {
            let groups = model.groups
            VStack(alignment: .leading, spacing: Self.groupSpacing) {
                if status.isAgentTabsAvailable == false {
                    NoticeBanner(text: "Agent Tabs plugin is not reachable in Rider: focusing and opening files won't work.", isWarning: true)
                }
                ForEach(groups) { group in
                    card(for: group, in: groups)
                }
                if groups.isEmpty {
                    Text("No running agents").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(20)
                }
            }
            .coordinateSpace(name: GroupDrag.coordinateSpace)
            .onPreferenceChange(CardFramesKey.self) { frames in
                if drag == nil {
                    cardFrames = frames
                }
            }
        }
        else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.isRefreshing ? "Reading agents…" : "agent-hub did not answer").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    private func card(for group: SessionGroup, in groups: [SessionGroup]) -> some View {
        let isDragged = drag?.groupId == group.id
        let isMergeTarget = drag.map { mergeTarget(of: $0, in: groups) == group.id } ?? false
        let offset = displacement(of: group, in: groups)

        return GroupCard(
            group: group,
            model: model,
            isForgottenExpanded: $isForgottenExpanded,
            isDragged: isDragged,
            isMergeTarget: isMergeTarget,
            onDragChanged: { value in drag = GroupDrag(groupId: group.id, translation: value.translation.height, pointerY: value.location.y) },
            onDragEnded: { finishDrag(in: groups) }
        )
        .background(GeometryReader { geometry in
            Color.clear.preference(key: CardFramesKey.self, value: [group.id: geometry.frame(in: .named(GroupDrag.coordinateSpace))])
        })
        .offset(y: offset)
        .zIndex(isDragged ? 1 : 0)
        .animation(isDragged ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: offset)
    }

    private func displacement(of group: SessionGroup, in groups: [SessionGroup]) -> CGFloat {
        guard let drag else { return 0 }
        if drag.groupId == group.id {
            return drag.translation
        }
        guard mergeTarget(of: drag, in: groups) == nil,
              let draggedFrame = cardFrames[drag.groupId],
              let target = targetIndex(of: drag, in: groups) else { return 0 }

        let order = groups.filter(\.isReorderable).map(\.id)
        guard let draggedIndex = order.firstIndex(of: drag.groupId), let index = order.firstIndex(of: group.id) else { return 0 }

        let shift = draggedFrame.height + Self.groupSpacing
        if draggedIndex < index && index <= target { return -shift }
        if target <= index && index < draggedIndex { return shift }
        return 0
    }

    private func targetIndex(of drag: GroupDrag, in groups: [SessionGroup]) -> Int? {
        guard let draggedFrame = cardFrames[drag.groupId] else { return nil }
        let draggedCenter = draggedFrame.midY + drag.translation
        return groups
            .filter { $0.isReorderable && $0.id != drag.groupId }
            .filter { (cardFrames[$0.id]?.midY ?? .infinity) < draggedCenter }
            .count
    }

    // In task mode, dropping onto another block's header merges the two tasks.
    private func mergeTarget(of drag: GroupDrag, in groups: [SessionGroup]) -> String? {
        guard model.groupingMode == .task else { return nil }
        return groups.first { group in
            guard group.isReorderable, group.id != drag.groupId, let frame = cardFrames[group.id] else { return false }
            return drag.pointerY >= frame.minY && drag.pointerY <= frame.minY + GroupCard.headerHeight
        }?.id
    }

    private func finishDrag(in groups: [SessionGroup]) {
        guard let finished = drag else { return }
        let merge = mergeTarget(of: finished, in: groups).flatMap { id in groups.first { $0.id == id } }
        let target = targetIndex(of: finished, in: groups)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if let merge {
                model.mergeTask(finished.groupId, into: merge)
            }
            else if let target {
                model.moveGroup(finished.groupId, to: target)
            }
            drag = nil
        }
    }
}

private struct GroupDrag {
    static let coordinateSpace = "groups"

    let groupId: String
    let translation: CGFloat
    let pointerY: CGFloat
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Header

private struct PanelHeader: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                Image(nsImage: MenuBarIcon.make(hasAttention: false))
                    .renderingMode(.template)
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Hub").font(.system(size: 14, weight: .semibold, design: .rounded))
                summary.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(GlassIconButtonStyle(diameter: 28))
            .disabled(model.isRefreshing)
            .help("Refresh now")
            SettingsMenu(model: model)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var summary: Text {
        guard let status = model.status else { return Text("Starting…") }
        let needing = status.sessions.filter(\.isNeedingUser).count
        let working = status.sessions.filter { $0.state == "working" }.count
        let counts = needing > 0 ? "\(needing) need you · \(working) working" : "Nothing waits for you · \(working) working"
        return Text("\(counts) · ") + Text(status.generatedAt, style: .relative) + Text(" ago")
    }
}

private struct SettingsMenu: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        Menu {
            Picker("Group by", selection: $model.groupingMode) {
                ForEach(GroupingMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Button("Reset group order") { model.resetGroupOrder() }
                .disabled(model.groupingMode.isReorderable == false)
            Divider()
            Toggle("Open edited files on focus", isOn: $model.isOpeningEditedFilesOnFocus)
            Divider()
            Button("Quit Agent Hub") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .glassCircle()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Grouping and settings")
    }
}

private struct NoticeBanner: View {
    let text: String
    var isWarning = false

    var body: some View {
        Label(text, systemImage: isWarning ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 12, tint: isWarning ? .orange : nil)
            .padding(.horizontal, isWarning ? 0 : 10)
            .padding(.top, isWarning ? 0 : 4)
    }
}

// MARK: - Group card

private struct GroupCard: View {
    static let headerHeight: CGFloat = 34

    let group: SessionGroup
    @ObservedObject var model: PanelModel
    @Binding var isForgottenExpanded: Bool
    let isDragged: Bool
    let isMergeTarget: Bool
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isCollapsed == false {
                VStack(spacing: 1) {
                    ForEach(group.sessions) { SessionRow(session: $0, isShowingProject: model.groupingMode != .project, model: model) }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        .glassSurface(cornerRadius: 16, tint: isMergeTarget ? .accentColor : nil, isRaised: isDragged)
        .overlay(alignment: .topTrailing) {
            if isMergeTarget {
                Label("Merge into \(group.title)", systemImage: "arrow.triangle.merge")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .scaleEffect(isDragged ? 1.02 : 1)
        .opacity(group.isForgotten ? 0.85 : 1)
    }

    private var isCollapsed: Bool { group.isForgotten && isForgottenExpanded == false }

    @ViewBuilder
    private var header: some View {
        let row = HStack(spacing: 7) {
            if group.isForgotten {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isForgottenExpanded ? 90 : 0))
            }
            else if group.isReorderable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            title
            CountPill(count: group.sessions.count)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.headerHeight)
        .contentShape(Rectangle())

        if group.isForgotten {
            row.onTapGesture { withAnimation(.easeOut(duration: 0.18)) { isForgottenExpanded.toggle() } }
        }
        else if group.isReorderable {
            row
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(GroupDrag.coordinateSpace))
                    .onChanged(onDragChanged)
                    .onEnded { _ in onDragEnded() })
                .contextMenu { contextMenu }
                .help(model.groupingMode == .task ? "Drag to reorder, drop on another task to merge, double-click to rename" : "Drag to reorder")
        }
        else {
            row
        }
    }

    @ViewBuilder
    private var title: some View {
        if model.groupingMode == .project && group.isReorderable {
            ProjectChip(name: group.title, size: 11)
        }
        else if model.groupingMode == .task && group.isReorderable {
            if isRenaming {
                TextField("Task name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($isNameFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
                    .frame(maxWidth: 220)
            }
            else {
                Text(group.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2, perform: startRename)
                ForEach(projectNames, id: \.self) { ProjectChip(name: $0) }
            }
        }
        else {
            Text(group.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if model.groupingMode == .task {
            Button("Rename…", action: startRename)
            Divider()
        }
        Button("Move to top") { model.moveGroup(group.id, by: -1000) }
        Button("Move up") { model.moveGroup(group.id, by: -1) }
        Button("Move down") { model.moveGroup(group.id, by: 1) }
    }

    private var projectNames: [String] {
        var seen: Set<String> = []
        return group.sessions.map(\.projectName).filter { seen.insert($0).inserted }
    }

    private func startRename() {
        draftName = group.title
        isRenaming = true
        DispatchQueue.main.async { isNameFieldFocused = true }
    }

    private func commitRename() {
        isRenaming = false
        model.renameTask(group, to: draftName)
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: PanelSession
    let isShowingProject: Bool
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
                    if isShowingProject {
                        ProjectChip(name: session.projectName)
                    }
                    Spacer(minLength: 4)
                    Text(IdleFormatter.format(session.idleSeconds))
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(isHovered ? 0.07 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture {
            if session.hasTerminalTab {
                model.showAgent(session)
            }
        }
        .help(session.hasTerminalTab ? focusHelp : "No Rider terminal tab found for this session")
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button { model.showAgent(session) } label: { Image(systemName: "terminal") }
                .disabled(session.hasTerminalTab == false)
                .help(focusHelp)
            if let unityPid = session.unityPid {
                Button { model.showUnityEditor(pid: unityPid) } label: { Image(systemName: "cube") }
                    .help("Show the \(session.projectName) Unity editor")
            }
            if session.artifactUrl != nil {
                Button { model.openArtifact(session) } label: { Image(systemName: "globe") }
                    .help("Open the page this agent published")
            }
        }
        .frame(width: 26 * 3 + 4 * 2, alignment: .leading)
        .buttonStyle(GlassIconButtonStyle(diameter: 26))
        .opacity(isHovered || session.isNeedingUser ? 1 : 0.5)
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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: color.opacity(0.35), radius: 3, y: 1)
            )
            .saturation(state == "idle" || state == "stale" ? 0.35 : 1)
    }

    private var symbol: String {
        switch state {
        case "waiting": return "questionmark"
        case "review": return "checkmark"
        case "working": return "ellipsis"
        case "stale": return "zzz"
        default: return "pause.fill"
        }
    }

    private var color: Color {
        switch state {
        case "waiting": return .orange
        case "review": return .green
        case "working": return .blue
        default: return .gray
        }
    }
}

// MARK: - Building blocks

private struct CountPill: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

private struct ProjectChip: View {
    let name: String
    var size: CGFloat = 10

    var body: some View {
        Text(name)
            .font(.system(size: size, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(ProjectPalette.color(for: name))
            .background(Capsule().fill(ProjectPalette.color(for: name).opacity(0.16)))
            .overlay(Capsule().strokeBorder(ProjectPalette.color(for: name).opacity(0.25), lineWidth: 0.5))
    }
}

private extension View {
    func glassSurface(cornerRadius: CGFloat, tint: Color? = nil, isRaised: Bool = false) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, isRaised: isRaised, isInteractive: false))
    }

    func glassCircle(isInteractive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Circle(), tint: nil, isRaised: false, isInteractive: isInteractive))
    }
}

// Real Liquid Glass on macOS 26 when built with the Xcode 26+ SDK; a material imitation otherwise.
private struct GlassSurface<SurfaceShape: InsettableShape>: ViewModifier {
    let shape: SurfaceShape
    let tint: Color?
    let isRaised: Bool
    let isInteractive: Bool

    func body(content: Content) -> some View {
        surface(content)
            .shadow(color: .black.opacity(isRaised ? 0.3 : 0), radius: isRaised ? 18 : 0, y: isRaised ? 10 : 0)
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content
                .glassEffect(makeGlass(), in: shape)
                .overlay(tint.map { shape.strokeBorder($0.opacity(0.7), lineWidth: 1.5) })
        }
        else {
            imitation(content)
        }
        #else
        imitation(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26, *)
    private func makeGlass() -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint.opacity(0.3))
        }
        return isInteractive ? glass.interactive() : glass
    }
    #endif

    private func imitation(_ content: Content) -> some View {
        content.background(
            shape
                .fill(.thinMaterial)
                .overlay(shape.fill((tint ?? .clear).opacity(0.12)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                .overlay(tint.map { shape.strokeBorder($0.opacity(0.7), lineWidth: 1.5) })
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        )
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    let diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        GlassIconButtonBody(configuration: configuration, diameter: diameter)
    }

    private struct GlassIconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let diameter: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: diameter * 0.44, weight: .medium))
                .frame(width: diameter, height: diameter)
                .foregroundStyle(isEnabled ? (isHovered ? Color.accentColor : Color.primary) : Color.secondary.opacity(0.5))
                .glassCircle(isInteractive: true)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Footer

private struct PanelFooter: View {
    let freeClones: [PanelClone]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("FREE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .fixedSize()
            FlowLayout(spacing: 4) {
                ForEach(freeClones) { ProjectChip(name: $0.name) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .help("Clones open in Rider or Unity with no agent and no local changes")
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
        return Color(hue: hueByProject[project] ?? hashedHue(project), saturation: 0.6, brightness: 0.85)
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
