import AppKit
import Carbon.HIToolbox

@main
@MainActor
enum AgentHubBarApp {
    private static var controller: StatusItemController?
    private static var hotKey: GlobalHotKey?

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.mainMenu = makeEditMenuBar()
        let statusItemController = StatusItemController(model: PanelModel())
        controller = statusItemController
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey) {
            DispatchQueue.main.async { statusItemController.togglePanel() }
        }
        if hotKey == nil {
            HubLog.write("could not register the Control-Option-Command-H hot key; another app may own it")
        }
        application.run()
    }

    // A menu bar app shows no menus, but text fields still need ⌘X, ⌘C, ⌘V and ⌘A, which only menu items deliver.
    private static func makeEditMenuBar() -> NSMenu {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        let menuBar = NSMenu()
        menuBar.addItem(editItem)
        return menuBar
    }
}
