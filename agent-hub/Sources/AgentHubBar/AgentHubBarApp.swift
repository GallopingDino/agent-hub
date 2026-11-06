import AppKit

@main
@MainActor
enum AgentHubBarApp {
    private static var controller: StatusItemController?

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        controller = StatusItemController(model: PanelModel())
        application.run()
    }
}
