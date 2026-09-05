import AppKit
import Foundation

/// 面板关掉后，双击的第二下会落到下面正在输入的窗口。用一块透明挡板吃掉这一下。
@MainActor
final class ClickThroughEater {
    private var panel: NSPanel?
    private var workItem: DispatchWorkItem?

    func cover(_ frame: NSRect, duration: TimeInterval) {
        cancel()
        let shield = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        shield.isOpaque = false
        shield.backgroundColor = .clear
        shield.hasShadow = false
        shield.level = .screenSaver
        shield.ignoresMouseEvents = false
        shield.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        shield.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        shield.orderFrontRegardless()
        panel = shield

        let work = DispatchWorkItem { [weak self] in
            self?.cancel()
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.2), execute: work)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
