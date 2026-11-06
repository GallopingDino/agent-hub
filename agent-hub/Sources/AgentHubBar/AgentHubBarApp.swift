import SwiftUI

@main
struct AgentHubBarApp: App {
    @StateObject private var model = PanelModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: MenuBarIcon.make(hasAttention: model.attentionCount > 0))
                if model.attentionCount > 0 {
                    Text("\(model.attentionCount)").monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
