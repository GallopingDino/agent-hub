import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// Own status item and panel instead of MenuBarExtra, which drifted away from the icon over full-screen apps.
@MainActor
final class StatusItemController: NSObject {
    private static let panelWidth: CGFloat = 480
    private static let gapBelowMenuBar: CGFloat = 6
    private static let cornerRadius: CGFloat = 20

    private let model: PanelModel
    private let statusItem: NSStatusItem
    private let panel: AnchoredPanel

    private var subscriptions: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var escapeHotKey: GlobalHotKey?
    private var panelTop: CGFloat = 0

    init(model: PanelModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AgentHubStatusItem"
        panel = AnchoredPanel()
        super.init()
        panel.onCancel = { [weak self] in self?.hidePanel() }

        configureStatusButton()
        configurePanel()
        model.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &subscriptions)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.imagePosition = .imageLeading
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let count = model.attentionCount
        button.image = MenuBarIcon.make(hasAttention: count > 0)
        button.title = count > 0 ? " \(count)" : ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func configurePanel() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidResize), name: NSWindow.didResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc func togglePanel() {
        if panel.isVisible {
            hidePanel()
        }
        else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panelTop = buttonFrame.minY - Self.gapBelowMenuBar

        let size = panel.contentView?.fittingSize ?? NSSize(width: Self.panelWidth, height: 400)
        let visible = screen.frame
        let x = min(max(buttonFrame.midX - Self.panelWidth / 2, visible.minX + 8), visible.maxX - Self.panelWidth - 8)
        panel.setFrame(NSRect(x: x, y: panelTop - size.height, width: Self.panelWidth, height: size.height), display: true)

        model.panelDidOpen()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        // The panel cannot take keyboard focus from the active app, so Esc is grabbed only while the panel is shown.
        escapeHotKey = GlobalHotKey(keyCode: kVK_Escape, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in self?.hidePanel() }
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        model.panelDidClose()
        escapeHotKey = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    // The list grows and shrinks with its content; keep the top edge pinned under the icon.
    @objc private func panelDidResize() {
        guard panel.isVisible else { return }
        var frame = panel.frame
        guard abs(frame.maxY - panelTop) > 0.5 else { return }
        frame.origin.y = panelTop - frame.height
        panel.setFrame(frame, display: true)
    }

    @objc private func applicationDidResignActive() {
        hidePanel()
    }
}

private final class AnchoredPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
