import AppKit
import SwiftUI

// A native NSMenu keeps the trigger button styled like the other glass buttons; SwiftUI's Menu draws its own bezel.
@MainActor
final class SettingsMenuPresenter: NSObject {
    private static let shownProjectCount = 10

    private unowned let model: PanelModel

    private var openMenu: NSMenu?

    var isOpen: Bool {
        openMenu != nil
    }

    init(model: PanelModel) {
        self.model = model
    }

    func show(at point: NSPoint?) {
        let menu = NSMenu()
        addUsageItems(to: menu)
        addRestartHandyItems(to: menu)
        addResetUsageItems(to: menu)
        addWakeUpItems(to: menu)
        addCloseUnusedItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(makeOpenProjectItem())
        menu.addItem(.separator())

        menu.addItem(makeHeader("Group by"))
        for mode in GroupingMode.allCases {
            let item = makeItem(mode.title, #selector(selectGroupingMode(_:)))
            item.representedObject = mode.rawValue
            item.state = model.groupingMode == mode ? .on : .off
            menu.addItem(item)
        }
        let reset = makeItem("Reset group order", #selector(resetGroupOrder))
        reset.isEnabled = model.groupingMode.isReorderable
        menu.addItem(reset)

        menu.addItem(.separator())
        let openFiles = makeItem("Open edited files on focus", #selector(toggleOpeningEditedFiles))
        openFiles.state = model.isOpeningEditedFilesOnFocus ? .on : .off
        menu.addItem(openFiles)
        menu.addItem(makeItem("Task Tracker Link…", #selector(editTaskLinkTemplate)))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Agent Hub", #selector(quit)))
        menu.addItem(makeCloseKeyItem())

        openMenu = menu
        model.onSettingsMenuToggled?()
        menu.popUp(positioning: nil, at: point ?? NSEvent.mouseLocation, in: nil)
        openMenu = nil
        model.onSettingsMenuToggled?()
    }

    private func addUsageItems(to menu: NSMenu) {
        if model.usage.isEmpty {
            menu.addItem(makeInfoItem("Usage is loading…"))
        }
        else {
            menu.addItem(makeUsageItem())
        }
    }

    // Offered whenever Handy runs, since a hang the log does not show is possible too; flagged when one is seen.
    // A view item carries no action, so the arrow keys pass over it.
    private func makeUsageItem() -> NSMenuItem {
        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: UsageMenuView(usage: model.usage))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        item.view = hosting
        return item
    }

    private func addRestartHandyItems(to menu: NSMenu) {
        guard model.isHandyFrozen else { return }
        menu.addItem(.separator())
        let restart = makeItem("Restart Handy", #selector(restartHandy))
        restart.isEnabled = model.isRestartingHandy == false
        restart.image = makeTemplateImage(of: FrozenHandyIcon())
        menu.addItem(restart)
    }

    // Only for an agent near a limit that still has a free reset to spend.
    private func addResetUsageItems(to menu: NSMenu) {
        let resettable = model.usage.filter { $0.isNearLimit && ($0.resetCount ?? 0) > 0 }
        guard resettable.isEmpty == false else { return }
        menu.addItem(.separator())
        let items = resettable.map { agentUsage in
            let item = makeItem("Reset \(agentUsage.agentName) Usage (\(agentUsage.resetCount ?? 0) left)", #selector(resetUsage(_:)))
            item.representedObject = agentUsage.agent
            item.isEnabled = model.isResettingUsage == false
            return item
        }
        items.first?.image = makeTemplateImage(of: LowBatteryIcon(placement: .menu))
        items.forEach(menu.addItem)
    }

    private func addWakeUpItems(to menu: NSMenu) {
        guard model.isAnyAgentAsleep else { return }
        menu.addItem(.separator())
        let wakeUp = makeItem("Wake Up Agents", #selector(wakeUpAgents))
        wakeUp.isEnabled = model.isWakingUpAgents == false
        wakeUp.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: nil)
        menu.addItem(wakeUp)
    }

    private func addCloseUnusedItems(to menu: NSMenu) {
        let clones = model.unusedClones
        guard clones.isEmpty == false else { return }
        menu.addItem(.separator())
        var items: [NSMenuItem] = []
        if clones.count > 1 {
            items.append(makeCloseUnusedItem("Close All Unused", closing: clones))
        }
        for clone in clones {
            items.append(makeCloseUnusedItem("Close Unused: \(clone.name)", closing: [clone]))
        }
        items.first?.image = makeTemplateImage(of: makeBroom())
        items.forEach(menu.addItem)
    }

    private func makeBroom() -> some View {
        BroomShape()
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .frame(width: 10, height: 13)
            .rotationEffect(.degrees(35))
            .frame(width: 16, height: 16)
    }

    private func makeTemplateImage(of view: some View) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }

    private func makeCloseUnusedItem(_ title: String, closing clones: [PanelClone]) -> NSMenuItem {
        let item = makeItem(title, #selector(closeUnusedClones(_:)))
        item.representedObject = clones.map(\.name)
        item.isEnabled = model.isClosingUnusedClones == false
        return item
    }

    // S closes the open menu the way it opened it; choosing any item closes the menu.
    private func makeCloseKeyItem() -> NSMenuItem {
        let item = makeItem("Close Menu", #selector(closeMenu))
        item.keyEquivalent = "s"
        item.keyEquivalentModifierMask = []
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    private func makeOpenProjectItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Open Project", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        item.submenu = makeProjectsMenu()
        return item
    }

    private func makeProjectsMenu() -> NSMenu {
        let menu = NSMenu()
        let projects = Array(model.recentProjects.prefix(Self.shownProjectCount))
        if projects.isEmpty {
            menu.addItem(makeInfoItem("No closed projects to open"))
        }

        let repeatedNames = Set(Dictionary(grouping: projects, by: \.name).filter { $0.value.count > 1 }.keys)
        for project in projects {
            let isShowingFolder = repeatedNames.contains(project.name)
            menu.addItem(makeProjectItem(project, isUnityWanted: false, isShowingFolder: isShowingFolder))
            if project.canChooseUnity {
                let withUnity = makeProjectItem(project, isUnityWanted: true, isShowingFolder: isShowingFolder)
                withUnity.isAlternate = true
                withUnity.keyEquivalentModifierMask = .option
                menu.addItem(withUnity)
            }
        }

        if projects.contains(where: \.canChooseUnity) {
            menu.addItem(.separator())
            menu.addItem(makeInfoItem("Hold ⌥ to also open Unity"))
        }
        return menu
    }

    // The icon and subtitle tell what one click opens; holding Option swaps in the twin that also opens Unity.
    private func makeProjectItem(_ project: PanelRecentProject, isUnityWanted: Bool, isShowingFolder: Bool) -> NSMenuItem {
        let item = makeItem(project.name, #selector(openProject(_:)))
        item.representedObject = project.directory
        item.keyEquivalentModifierMask = []
        let symbol = project.isOpeningUnity(whenWanted: isUnityWanted) ? "cube" : "chevron.left.forwardslash.chevron.right"
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if isShowingFolder {
            let title = NSMutableAttributedString(string: project.name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: "  \(project.parentFolderName)", attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = title
        }
        setSubtitle(project.describeLaunch(isUnityWanted: isUnityWanted), of: item)
        return item
    }

    private func setSubtitle(_ subtitle: String, of item: NSMenuItem) {
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        }
        else {
            item.title += " — \(subtitle)"
        }
    }

    private func makeHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        return makeInfoItem(title)
    }

    private func makeInfoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func closeMenu() {
    }

    @objc private func resetUsage(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? String, let agentUsage = model.usage.first(where: { $0.agent == agent }) else { return }
        model.resetUsage(of: agentUsage)
    }

    // The panel's agents carry task codes such as BR-1566; this link turns one into a page in the tracker.
    func askForTaskLinkTemplate() {
        let alert = NSAlert()
        alert.messageText = "Task Tracker Link"
        alert.informativeText = "Agents report their tasks as codes or links. A code opens through this link, with {code} replaced by the code."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://app.asana.com/0/search?q={code}"
        field.stringValue = model.taskLinkTemplate
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        // The panel's Return and Space keys would otherwise swallow typing in the field.
        model.isEditingName = true
        defer { model.isEditingName = false }
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.taskLinkTemplate = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func editTaskLinkTemplate() {
        askForTaskLinkTemplate()
    }

    @objc private func restartHandy() {
        model.restartHandy()
    }

    @objc private func wakeUpAgents() {
        model.wakeUpAgents()
    }

    @objc private func closeUnusedClones(_ sender: NSMenuItem) {
        guard let names = sender.representedObject as? [String] else { return }
        model.closeUnusedClones(model.unusedClones.filter { names.contains($0.name) })
    }

    @objc private func openProject(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? String, let project = model.recentProjects.first(where: { $0.directory == directory }) else { return }
        model.openProject(project, isUnityWanted: sender.isAlternate)
    }

    @objc private func selectGroupingMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = GroupingMode(rawValue: raw) else { return }
        model.groupingMode = mode
    }

    @objc private func resetGroupOrder() {
        model.resetGroupOrder()
    }

    @objc private func toggleOpeningEditedFiles() {
        model.isOpeningEditedFilesOnFocus.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
