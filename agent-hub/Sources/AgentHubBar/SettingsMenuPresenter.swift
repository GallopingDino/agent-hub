import AppKit

// A native NSMenu keeps the trigger button styled like the other glass buttons; SwiftUI's Menu draws its own bezel.
@MainActor
final class SettingsMenuPresenter: NSObject {
    private let model: PanelModel

    init(model: PanelModel) {
        self.model = model
    }

    func show() {
        let menu = NSMenu()
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

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func makeHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
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
