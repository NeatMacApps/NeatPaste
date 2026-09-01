import AppKit
import SwiftUI

/// 隐藏菜单栏图标后的恢复面。普通带标题栏窗口，可以激活本应用；不是历史面板。
@MainActor
final class RecoveryWindowController: NSObject, NSWindowDelegate {
    static let shared = RecoveryWindowController()

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: RecoveryView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "recovery.title")
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
        TitledWindowActivation.windowWillClose()
    }
}
