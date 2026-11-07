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
    private static let headerInset: CGFloat = 22
    private static let headerTopPadding: CGFloat = 12
    private static let headerButtonDiameter: CGFloat = 26

    private let model: PanelModel
    private let statusItem: NSStatusItem
    private let panel: AnchoredPanel

    private var subscriptions: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var panelClickMonitor: Any?
    private var escapeHotKey: GlobalHotKey?
    private var refreshHotKey: GlobalHotKey?
    private var settingsHotKey: GlobalHotKey?
    private var previousSessionHotKey: GlobalHotKey?
    private var nextSessionHotKey: GlobalHotKey?
    private var closeSessionHotKey: GlobalHotKey?
    private var returnHotKey: GlobalHotKey?
    private var showTerminalHotKey: GlobalHotKey?
    private var renameHotKey: GlobalHotKey?
    private var previousChoiceHotKey: GlobalHotKey?
    private var nextChoiceHotKey: GlobalHotKey?
    private var panelTop: CGFloat = 0

    init(model: PanelModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AgentHubStatusItem"
        panel = AnchoredPanel()
        super.init()
        panel.onCancel = { [weak self] in self?.hidePanel() }
        model.onLeavingForEditor = { [weak self] in self?.hidePanel() }
        // The menu runs its own event loop, so the keys are released right away instead of through a publisher.
        model.onSettingsMenuToggled = { [weak self] in
            guard let self else { return }
            self.updateEscapeHotKey()
            self.updateLetterHotKeys(isEditingName: self.model.isEditingName)
            self.updateClosingHotKeys()
        }

        configureStatusButton()
        configurePanel()
        model.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &subscriptions)
        model.$usage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &subscriptions)
        model.$isEditingName
            .receive(on: RunLoop.main)
            .sink { [weak self] isEditing in
                self?.updateLetterHotKeys(isEditingName: isEditing)
                self?.updateClosingHotKeys()
            }
            .store(in: &subscriptions)
        model.$selectedSessionId.combineLatest(model.$confirmingCloseSessionId)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateClosingHotKeys() }
            .store(in: &subscriptions)
        panelClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.finishEditingUnlessClickedInside(event)
            return event
        }
    }

    // A click anywhere else in the panel ends a rename the way Return does.
    private func finishEditingUnlessClickedInside(_ event: NSEvent) {
        guard event.window === panel, let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor else { return }
        let point = editor.convert(event.locationInWindow, from: nil)
        if editor.bounds.contains(point) == false {
            panel.makeFirstResponder(nil)
        }
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
        button.image = MenuBarIcon.make(hasAttention: count > 0 || model.isAnyAgentAsleep)
        button.title = count > 0 ? " \(count)" : ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func configurePanel() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.makeCornerMask()
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

    // The layer corner radius only clips drawing; the window server needs the mask to round the backdrop blur and shadow.
    private static func makeCornerMask() -> NSImage {
        let cap = (cornerRadius * 1.6).rounded(.up)
        let edge = cap * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect).cgPath)
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
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
        updateEscapeHotKey()
        updateLetterHotKeys(isEditingName: model.isEditingName)
        updateClosingHotKeys()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        model.panelDidClose()
        updateEscapeHotKey()
        updateLetterHotKeys(isEditingName: model.isEditingName)
        updateClosingHotKeys()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    // The panel cannot take keyboard focus from the active app, so its keys are grabbed only while it is shown.
    // An open settings menu gets Escape itself and closes on it.
    private func updateEscapeHotKey() {
        guard panel.isVisible, model.isSettingsMenuOpen == false else {
            escapeHotKey = nil
            return
        }
        guard escapeHotKey == nil else { return }

        escapeHotKey = GlobalHotKey(keyCode: kVK_Escape, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.model.confirmingCloseSessionId != nil {
                    self.model.cancelClosing()
                }
                else if self.model.selectedSessionId != nil {
                    self.model.deselectSession()
                }
                else {
                    self.hidePanel()
                }
            }
        }
    }

    // R refreshes, S opens the settings menu and the arrows move the selection, only while the panel is shown and no name is being typed.
    // An open menu gets every key itself: hot keys pressed during it would only fire after it closes.
    private func updateLetterHotKeys(isEditingName: Bool) {
        guard panel.isVisible, isEditingName == false, model.isSettingsMenuOpen == false else {
            refreshHotKey = nil
            settingsHotKey = nil
            previousSessionHotKey = nil
            nextSessionHotKey = nil
            return
        }
        guard refreshHotKey == nil else { return }

        settingsHotKey = GlobalHotKey(keyCode: kVK_ANSI_S, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Not from inside this main-queue block: the menu's own loop would hold the queue.
                RunLoop.main.perform { self.model.showSettingsMenu(at: self.findSettingsMenuPoint()) }
            }
        }

        refreshHotKey = GlobalHotKey(keyCode: kVK_ANSI_R, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in
                guard let model = self?.model else { return }
                Task { await model.refresh() }
            }
        }
        previousSessionHotKey = GlobalHotKey(keyCode: kVK_UpArrow, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in self?.moveSelection(by: -1) }
        }
        nextSessionHotKey = GlobalHotKey(keyCode: kVK_DownArrow, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in self?.moveSelection(by: 1) }
        }
    }

    private func moveSelection(by offset: Int) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { model.selectAdjacentSession(by: offset) }
    }

    // For the selected agent: Control-X closes its tab, Command-Down shows it, Option-Tab renames it, Left and Right move between its buttons or answers, Return activates.
    private func updateClosingHotKeys() {
        let isActive = panel.isVisible && model.isEditingName == false && model.isSettingsMenuOpen == false && model.selectedSessionId != nil
        guard isActive else {
            closeSessionHotKey = nil
            returnHotKey = nil
            showTerminalHotKey = nil
            renameHotKey = nil
            previousChoiceHotKey = nil
            nextChoiceHotKey = nil
            return
        }
        guard closeSessionHotKey == nil else { return }

        closeSessionHotKey = GlobalHotKey(keyCode: kVK_ANSI_X, modifiers: controlKey) {
            DispatchQueue.main.async { [weak self] in self?.model.closeSelectedSession() }
        }
        returnHotKey = GlobalHotKey(keyCode: kVK_Return, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in self?.model.activateSelection() }
        }
        showTerminalHotKey = GlobalHotKey(keyCode: kVK_DownArrow, modifiers: cmdKey) {
            DispatchQueue.main.async { [weak self] in self?.model.showSelectedSessionTerminal() }
        }
        renameHotKey = GlobalHotKey(keyCode: kVK_Tab, modifiers: optionKey) {
            DispatchQueue.main.async { [weak self] in self?.model.startRenamingSelection() }
        }
        previousChoiceHotKey = GlobalHotKey(keyCode: kVK_LeftArrow, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in self?.model.moveHighlight(by: -1) }
        }
        nextChoiceHotKey = GlobalHotKey(keyCode: kVK_RightArrow, modifiers: 0) {
            DispatchQueue.main.async { [weak self] in self?.model.moveHighlight(by: 1) }
        }
    }

    // Under the settings button, which sits in the header's top-right corner.
    private func findSettingsMenuPoint() -> NSPoint {
        NSPoint(x: panel.frame.maxX - Self.headerInset - Self.headerButtonDiameter, y: panel.frame.maxY - Self.headerTopPadding - Self.headerButtonDiameter - 4)
    }

    // The list grows and shrinks with its content; keep the top edge pinned under the icon.
    @objc private func panelDidResize() {
        guard panel.isVisible else { return }
        panel.invalidateShadow()
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
