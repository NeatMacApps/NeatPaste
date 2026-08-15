import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var previousPolicy: NSApplication.ActivationPolicy?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "settings.title")
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        if NSApp.activationPolicy() == .accessory {
            previousPolicy = .accessory
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        HotkeyManager.shared.stopRecording()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        previousPolicy = nil
    }
}
