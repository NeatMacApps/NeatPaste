import AppKit
import ApplicationServices
import Foundation

enum PanelAnchor {
    static func frame(for size: NSSize) -> NSRect {
        let screen = targetScreen()
        let visible = screen.visibleFrame
        let clampedSize = NSSize(
            width: min(size.width, max(240, visible.width - 16)),
            height: min(size.height, max(180, visible.height - 16))
        )
        let origin = origin(for: clampedSize, on: visible, preferredRect: preferredAnchorRect())
        return NSRect(origin: origin, size: clampedSize)
    }

    private static func origin(for size: NSSize, on visible: NSRect, preferredRect: NSRect?) -> NSPoint {
        var x: CGFloat
        var y: CGFloat
        if let preferredRect {
            x = preferredRect.midX - size.width / 2
            y = preferredRect.minY - size.height - 12
            if y < visible.minY + 8 {
                y = preferredRect.maxY + 12
            }
        } else {
            x = visible.midX - size.width / 2
            y = visible.minY + visible.height * 0.62 - size.height / 2
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private static func targetScreen() -> NSScreen {
        if let rect = preferredAnchorRect() {
            return screen(containing: NSPoint(x: rect.midX, y: rect.midY)) ?? NSScreen.main ?? NSScreen.screens[0]
        }
        return screen(containing: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func preferredAnchorRect() -> NSRect? {
        if let focused = focusedElementCocoaRect(), focused.width > 0, focused.height > 0 {
            return focused
        }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y, width: 2, height: 16)
    }

    private static func focusedElementCocoaRect() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else {
            return nil
        }
        let element = focusedRef as! AXUIElement
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        return cocoaRect(fromAX: CGRect(origin: position, size: size))
    }

    /// 辅助功能坐标系原点在主屏左上，AppKit 在左下。
    private static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let primary else { return rect }
        let y = primary.frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }
}
