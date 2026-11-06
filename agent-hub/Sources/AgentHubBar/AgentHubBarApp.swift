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
}
