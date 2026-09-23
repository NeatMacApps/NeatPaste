import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            // 内容变高后窗口跟着撑开：460x460 的初始框只定起点，不裁内容。
            hosting.sizingOptions = [.intrinsicContentSize]
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

        let wasVisible = window?.isVisible == true
        if !wasVisible {
            TitledWindowActivation.windowDidShow()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        HotkeyManager.shared.stopRecording()
        TitledWindowActivation.windowWillClose()
    }
}
