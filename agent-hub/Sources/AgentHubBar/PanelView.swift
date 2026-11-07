import SwiftUI

struct PanelView: View {
    private static let maxListHeight: CGFloat = 600
    private static let groupSpacing: CGFloat = 10

    @ObservedObject var model: PanelModel
    @State private var listHeight: CGFloat = 120
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var drag: GroupDrag?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model)
            if let notice = model.notice {
                NoticeBanner(text: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollViewReader { scroller in
                ScrollView {
                    content
                        .padding(10)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: ListHeightKey.self, value: geometry.size.height)
                        })
                }
                .onChange(of: model.selectedSessionId) { _, selectedId in
                    guard let selectedId else { return }
                    withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(selectedId) }
                }
            }
            .frame(height: min(listHeight, Self.maxListHeight))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
        }
        .frame(width: 480)
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.2), value: model.notice)
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
            isInactiveExpanded: $model.isInactiveExpanded,
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
        HStack(spacing: 7) {
            Image(nsImage: MenuBarIcon.make(hasAttention: false))
                .renderingMode(.template)
                .resizable()
                .frame(width: 24, height: 19.2)
                .foregroundStyle(.secondary)
            Text("Agent Hub").font(.system(size: 17, weight: .semibold))
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
            .buttonStyle(GlassIconButtonStyle(diameter: 26))
            .disabled(model.isRefreshing)
            .help("Refresh now")
            SettingsMenu(model: model)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }
}

private struct SettingsMenu: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        Button {
            model.showSettingsMenu()
        } label: {
            if model.isWakingUpAgents || model.isClosingUnusedClones || model.isRestartingHandy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            else if model.isHandyFrozen {
                FrozenHandyIcon()
            }
            else if model.isAnyAgentAsleep {
                Image(systemName: "moon.zzz")
            }
            else if model.unusedClones.isEmpty == false {
                BroomShape()
                    .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 15)
                    .rotationEffect(.degrees(35))
            }
            else if model.isAnyAgentNearLimit {
                Image(systemName: "battery.25percent").foregroundStyle(UsageMenuView.nearLimitColor)
            }
            else {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .buttonStyle(GlassIconButtonStyle(diameter: 26))
        .help(helpText)
    }

    private var helpText: String {
        if model.isHandyFrozen { return "Usage and settings: Handy hangs while starting to record" }
        if model.isAnyAgentAsleep { return "Usage and settings: an agent has no 5-hour session" }
        if model.unusedClones.isEmpty == false { return "Usage and settings: clones are open with no agent and no local changes" }
        if model.isAnyAgentNearLimit { return "Usage and settings: an agent has used 80% or more of a limit" }
        return "Usage and settings"
    }
}

// Handy's open hand.
struct FrozenHandyIcon: View {
    var body: some View {
        Image(systemName: "hand.raised.fingers.spread")
            .font(.system(size: 14))
    }
}

// A handle over a bound bundle of bristles, drawn upright; SF Symbols has no broom.
struct BroomShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let bandTop = height * 0.5
        let bristlesTop = height * 0.6
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: bandTop))
        path.addRect(CGRect(x: width * 0.25, y: bandTop, width: width * 0.5, height: bristlesTop - bandTop))
        path.move(to: CGPoint(x: width * 0.25, y: bristlesTop))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: width * 0.75, y: bristlesTop))
        path.move(to: CGPoint(x: width * 0.42, y: bristlesTop))
        path.addLine(to: CGPoint(x: width * 0.33, y: rect.maxY))
        path.move(to: CGPoint(x: width * 0.58, y: bristlesTop))
        path.addLine(to: CGPoint(x: width * 0.67, y: rect.maxY))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct NoticeBanner: View {
    let text: String
    var isWarning = false

    var body: some View {
        Label(text, systemImage: isWarning ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
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
    @Binding var isInactiveExpanded: Bool
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
        .opacity(group.isInactive ? 0.85 : 1)
    }

    private var isCollapsed: Bool { group.isInactive && isInactiveExpanded == false }

    @ViewBuilder
    private var header: some View {
        let row = HStack(spacing: 7) {
            if group.isInactive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isInactiveExpanded ? 90 : 0))
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

        if group.isInactive {
            row.onTapGesture { withAnimation(.easeOut(duration: 0.18)) { isInactiveExpanded.toggle() } }
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
                    .onAppear { model.isEditingName = true }
                    .onDisappear { model.isEditingName = false }
                    .onChange(of: isNameFieldFocused) { _, isFocused in
                        if isFocused == false { commitRename() }
                    }
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
        guard isRenaming else { return }
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
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    private static let expandedLineLimit = 4
    private static let selectionAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)
    private static let selectionColor = Color(red: 185 / 255, green: 154 / 255, blue: 1).opacity(28 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { withAnimation(Self.selectionAnimation) { model.toggleSelection(session) } })
            if isSelected {
                SessionSelectionFooter(session: session, model: model)
                    .padding(.leading, StateBadge.size + 10)
                    .padding(.top, 8)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .opacity(isClosing ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .animation(Self.selectionAnimation, value: isSelected)
        .animation(Self.selectionAnimation, value: model.confirmingCloseSessionId)
        .animation(.easeOut(duration: 0.2), value: isClosing)
    }

    private var isSelected: Bool { model.selectedSessionId == session.id }

    private var isClosing: Bool { model.closingSessionIds.contains(session.id) }

    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return ZStack {
            shape.fill(Color.primary.opacity(isHovered && isSelected == false ? 0.06 : 0))
            shape.fill(Self.selectionColor).opacity(isSelected ? 1 : 0)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 10) {
            StateBadge(state: session.state, agent: session.agent)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    title
                    if isShowingProject {
                        ProjectChip(name: session.projectName)
                    }
                    Spacer(minLength: 4)
                    Text(IdleFormatter.format(session.idleSeconds))
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if isClosing {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Closing…")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                else if let detail = detailText {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(isSelected ? Self.expandedLineLimit : (session.isNeedingUser ? 2 : 1))
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    @ViewBuilder
    private var title: some View {
        if isRenaming {
            TextField("Session name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isNameFieldFocused)
                .onSubmit(commitRename)
                .onExitCommand { isRenaming = false }
                .onAppear { model.isEditingName = true }
                .onDisappear { model.isEditingName = false }
                .onChange(of: isNameFieldFocused) { _, isFocused in
                    if isFocused == false { commitRename() }
                }
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                .frame(maxWidth: 220)
        }
        else {
            Text(session.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .onTapGesture(count: 2, perform: startRename)
                .help("Double-click to rename the session")
                .onChange(of: model.renamingSessionId) { _, sessionId in
                    guard sessionId == session.id else { return }
                    model.finishRenameRequest()
                    startRename()
                }
        }
    }

    private func startRename() {
        draftName = session.title
        isRenaming = true
        DispatchQueue.main.async { isNameFieldFocused = true }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        model.renameSession(session, to: draftName)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            actionButton(.showTerminal, systemImage: "terminal")
                .disabled(session.hasTerminalTab == false)
                .help(focusHelp)
            if session.unityPid != nil {
                actionButton(.showUnity, systemImage: "cube")
                    .help("Show the \(session.projectName) Unity editor")
            }
            if session.artifactUrl != nil {
                actionButton(.openArtifact, systemImage: "globe")
                    .help("Open the page this agent published")
            }
        }
        .buttonStyle(GlassIconButtonStyle(diameter: 26))
        .opacity(isHovered || isSelected || session.isNeedingUser ? 1 : 0.5)
    }

    private func actionButton(_ action: SessionAction, systemImage: String) -> some View {
        Button { model.perform(action, for: session) } label: { Image(systemName: systemImage) }
        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(isSelected && model.confirmingCloseSessionId != session.id && model.highlightedSessionAction == action ? 1 : 0))
    }

    private var detailText: String? {
        if let waitingFor = session.waitingFor, waitingFor.isEmpty == false {
            return waitingFor.prefix(1).uppercased() + waitingFor.dropFirst()
        }
        return session.lastMessageExcerpt ?? session.lastMessagePreview
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

// MARK: - Selection footer

// Says what Control-X and Option-Tab will do, and asks before the last agent of a project takes its editors with it.
private struct SessionSelectionFooter: View {
    let session: PanelSession
    @ObservedObject var model: PanelModel

    var body: some View {
        if model.confirmingCloseSessionId == session.id {
            confirmation
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
        }
        else {
            HStack(spacing: 6) {
                if session.hasTerminalTab {
                    KeyCap(text: "⌃X")
                    Text("Close terminal tab")
                        .padding(.trailing, 6)
                }
                KeyCap(text: "⌥⇥")
                Text("Rename")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .transition(.opacity)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.orange)
                Text("Last agent in \(session.projectName). Close \(editorsText) too?")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11, weight: .medium))

            HStack(spacing: 6) {
                optionButton("Close All", option: .closeAll)
                optionButton("Tab Only", option: .tabOnly)
                Spacer(minLength: 0)
                optionButton("Cancel", option: .cancel)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private func optionButton(_ title: String, option: CloseConfirmationOption) -> some View {
        Button(title) { model.choose(option, for: session) }
        .buttonStyle(FooterButtonStyle(isProminent: model.highlightedCloseOption == option))
    }

    private var editorsText: String {
        session.unityPid == nil ? "the Rider window" : "the Rider window and Unity"
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4.5)
            .frame(minWidth: 18, minHeight: 15)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

private struct FooterButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .background(Capsule().fill(isProminent ? Color.orange : Color.primary.opacity(0.08)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct StateBadge: View {
    static let size: CGFloat = 26

    let state: String
    let agent: String?

    var body: some View {
        stateCircle
            .overlay(alignment: .bottomTrailing) {
                if let agent {
                    AgentMark(agent: agent).offset(x: 4, y: 4)
                }
            }
    }

    private var stateCircle: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
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

private struct AgentMark: View {
    let agent: String

    var body: some View {
        glyph
            .foregroundStyle(.primary)
            .frame(width: 16, height: 16)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
            .help(agent == "codex" ? "Codex" : "Claude Code")
    }

    private var glyph: some View {
        Image(nsImage: AgentLogo.image(for: agent))
            .resizable()
            .renderingMode(.template)
            .frame(width: 10, height: 10)
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
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, isRaised: isRaised, isInteractive: false, isRefracting: false))
    }

    func glassCircle(isInteractive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Circle(), tint: nil, isRaised: false, isInteractive: isInteractive, isRefracting: true))
    }
}

// Real Liquid Glass on macOS 26 when built with the Xcode 26+ SDK; a material imitation otherwise.
// Large cards skip real glass: its edge lensing pulls the panel border and header into them.
private struct GlassSurface<SurfaceShape: InsettableShape>: ViewModifier {
    let shape: SurfaceShape
    let tint: Color?
    let isRaised: Bool
    let isInteractive: Bool
    let isRefracting: Bool

    func body(content: Content) -> some View {
        surface(content)
            .shadow(color: .black.opacity(isRaised ? 0.3 : 0), radius: isRaised ? 18 : 0, y: isRaised ? 10 : 0)
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if isRefracting, #available(macOS 26, *) {
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

enum ProjectPalette {
    private static let hues: [Double] = [0.58, 0.08, 0.36, 0.78, 0.97, 0.47, 0.14, 0.68, 0.25, 0.88, 0.52]
    private static let hueByProject = loadHueByProject()

    // Parallel clones share their main project's colour.
    static func color(for cloneName: String) -> Color {
        let project = cloneName.replacingOccurrences(of: "-parallel", with: "")
        return Color(hue: hueByProject[project] ?? hashedHue(project), saturation: 0.6, brightness: 0.85)
    }

    private static func loadHueByProject() -> [String: Double] {
        let configFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/agent-hub/config.json")
        guard let data = try? Data(contentsOf: configFile) else { return [:] }
        return (try? JSONDecoder().decode(PaletteConfig.self, from: data))?.projectHues ?? [:]
    }

    private static func hashedHue(_ project: String) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in project.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hues[Int(hash % UInt64(hues.count))]
    }
}

private struct PaletteConfig: Decodable {
    let projectHues: [String: Double]
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
