import AppKit

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

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Agent Hub", #selector(quit)))

        openMenu = menu
        menu.popUp(positioning: nil, at: point ?? NSEvent.mouseLocation, in: nil)
        openMenu = nil
    }

    func close() {
        openMenu?.cancelTracking()
    }

    private func addUsageItems(to menu: NSMenu) {
        if model.isAnyAgentAsleep {
            let wakeUp = makeItem("Wake Up Agents", #selector(wakeUpAgents))
            wakeUp.isEnabled = model.isWakingUpAgents == false
            menu.addItem(wakeUp)
        }
        if model.usage.isEmpty {
            menu.addItem(makeInfoItem("Usage is loading…"))
        }
        for agentUsage in model.usage {
            menu.addItem(makeHeader(agentUsage.agentName))
            menu.addItem(makeInfoItem(agentUsage.summary))
        }
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

    @objc private func wakeUpAgents() {
        model.wakeUpAgents()
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
