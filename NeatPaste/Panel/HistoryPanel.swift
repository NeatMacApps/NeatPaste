import AppKit
import SwiftUI

@MainActor
final class HistoryPanel: NSPanel {
    private let model: HistoryPanelModel
    private var hostingView: NSHostingView<HistoryPanelView>?
    private var keyMonitor: Any?

    init(model: HistoryPanelModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: AppPreferences.panelSize),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Chrome 自动填充浮层 window layer 是 999，screenSaver(1000) 刚好盖住。
        level = .screenSaver
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 480, height: 280)

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let hosting = NSHostingView(rootView: HistoryPanelView(model: model))
        hosting.frame = contentRect(forFrameRect: frame)
        hosting.autoresizingMask = [.width, .height]
        hostingView = hosting
        contentView = makeChromeView(hosting)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showPanel() {
        setFrame(PanelAnchor.frame(for: AppPreferences.panelSize), display: true)
        // 剪贴板工具绝对不能 NSApp.activate，否则粘贴会贴到自己身上。
        orderFrontRegardless()
        makeKey()
        installKeyMonitor()
    }

    func hidePanel() {
        removeKeyMonitor()
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        if SettingsWindowController.shared.isVisible { return }
        hidePanel()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if let client = firstResponder as? NSTextInputClient, client.hasMarkedText() {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers == "," {
            SettingsWindowController.shared.show()
            return nil
        }

        switch Int(event.keyCode) {
        case 126: // ↑
            model.moveSelection(-1)
            return nil
        case 125: // ↓
            model.moveSelection(1)
            return nil
        case 36, 76: // Return / keypad Enter
            Task { await model.confirmPaste() }
            return nil
        case 53: // Escape
            hidePanel()
            return nil
        default:
            return event
        }
    }

    private func makeChromeView(_ hostingView: NSHostingView<HistoryPanelView>) -> NSView {
        let frame = NSRect(origin: .zero, size: AppPreferences.panelSize)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            glass.contentView = hostingView
            return glass
        }

        let effect = NSVisualEffectView(frame: frame)
        effect.autoresizingMask = [.width, .height]
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.addSubview(hostingView)
        hostingView.frame = effect.bounds
        hostingView.autoresizingMask = [.width, .height]
        return effect
    }
}
