import AppKit
import SwiftUI

/// Routes existing AppKit entry points to the single SwiftUI Settings scene.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private weak var window: NSWindow?
    private var presentSettings: (() -> Void)?
    private var presentationPending = false
    private var activationStarted = false

    var isVisible: Bool { window?.isVisible == true }

    func installPresenter(_ present: @escaping () -> Void) {
        presentSettings = present
        if presentationPending {
            show()
        }
    }

    func show() {
        guard let presentSettings else {
            presentationPending = true
            return
        }
        presentationPending = false
        beginActivation()
        presentSettings()
        NSApplication.shared.activate()
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        if let previous = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: previous)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: previous)
        }
        self.window = window
        window.setFrameAutosaveName("Settings")
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window
        )
    }

    func close() {
        if HotkeyManager.shared.isRecording {
            HotkeyManager.shared.stopRecording()
        } else {
            window?.performClose(nil)
        }
    }

    private func beginActivation() {
        guard !activationStarted else { return }
        activationStarted = true
        TitledWindowActivation.windowDidShow()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        beginActivation()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        HotkeyManager.shared.stopRecording()
        if activationStarted {
            activationStarted = false
            TitledWindowActivation.windowWillClose()
        }
    }
}

/// Observes the native scene window without replacing its delegate or controls.
struct SettingsWindowAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowAnchor { SettingsWindowAnchor() }
    func updateNSView(_ nsView: SettingsWindowAnchor, context: Context) {}
}

final class SettingsWindowAnchor: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            SettingsWindowController.shared.attach(to: window)
        }
    }
}
