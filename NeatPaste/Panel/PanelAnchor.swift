import AppKit
import ApplicationServices
import Darwin
import Foundation

enum PanelAnchor {
    /// 过大的输入框（整页编辑器、网页）不能当光标用，否则面板会落到窗口最底下。
    nonisolated static let largeFieldHeight: CGFloat = 140
    nonisolated static let largeFieldWidth: CGFloat = 720

    static func frame(for size: NSSize) -> NSRect {
        let preferred = preferredAnchorRect()
        let screen = targetScreen(preferredRect: preferred)
        let visible = screen.visibleFrame
        let clampedSize = NSSize(
            width: min(size.width, max(240, visible.width - 16)),
            height: min(size.height, max(180, visible.height - 16))
        )
        let origin = origin(for: clampedSize, on: visible, preferredRect: preferred)
        return NSRect(origin: origin, size: clampedSize)
    }

    nonisolated static func origin(for size: NSSize, on visible: NSRect, preferredRect: NSRect?) -> NSPoint {
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

    /// 大输入区域收成靠近鼠标或区域中心的小锚点，避免按整框底边摆面板。
    nonisolated static func compactAnchor(from rect: NSRect, mouse: NSPoint) -> NSRect {
        let tooBig = rect.height > largeFieldHeight || rect.width > largeFieldWidth
        guard tooBig else { return rect }
        if rect.contains(mouse) {
            return NSRect(x: mouse.x, y: mouse.y - 8, width: 2, height: 16)
        }
        return NSRect(x: rect.midX, y: rect.midY, width: 2, height: 16)
    }

    private static func targetScreen(preferredRect: NSRect?) -> NSScreen {
        if let preferredRect {
            return screen(containing: NSPoint(x: preferredRect.midX, y: preferredRect.midY))
                ?? NSScreen.main
                ?? NSScreen.screens[0]
        }
        return screen(containing: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func preferredAnchorRect() -> NSRect? {
        if let caret = focusedCaretCocoaRect() {
            NSLog("[NeatPaste] 面板锚点：输入光标")
            return caret
        }
        if let field = focusedFieldCocoaRect() {
            let compact = compactAnchor(from: field, mouse: NSEvent.mouseLocation)
            NSLog("[NeatPaste] 面板锚点：输入框")
            return compact
        }
        let mouse = NSEvent.mouseLocation
        NSLog("[NeatPaste] 面板锚点：鼠标")
        return NSRect(x: mouse.x, y: mouse.y, width: 2, height: 16)
    }

    private static func focusedCaretCocoaRect() -> NSRect? {
        guard let element = focusedElementExcludingSelf() else { return nil }
        if let caret = caretRect(of: element) {
            return cocoaRect(fromAX: caret)
        }
        return descendantCaretCocoaRect(of: element, depth: 3)
    }

    private static func focusedFieldCocoaRect() -> NSRect? {
        guard let element = focusedElementExcludingSelf(),
              let frame = elementFrame(element),
              frame.width > 0,
              frame.height > 0
        else {
            return nil
        }
        return cocoaRect(fromAX: frame)
    }

    private static func focusedElementExcludingSelf() -> AXUIElement? {
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
        if isOwnProcess(element) {
            return nil
        }
        return element
    }

    private static func isOwnProcess(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        return pid == getpid()
    }

    private static func descendantCaretCocoaRect(of element: AXUIElement, depth: Int) -> NSRect? {
        guard depth > 0 else { return nil }
        let kids = children(of: element).prefix(24)
        for child in kids {
            if let caret = caretRect(of: child) {
                return cocoaRect(fromAX: caret)
            }
        }
        for child in kids {
            if let nested = descendantCaretCocoaRect(of: child, depth: depth - 1) {
                return nested
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement]
        else {
            return []
        }
        return array
    }

    private static func caretRect(of element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else {
            return nil
        }

        if let rect = bounds(of: element, range: rangeRef), isUsableCaret(rect) {
            return normalized(rect)
        }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }
        let fallbacks: [CFRange] = [
            CFRange(location: cfRange.location, length: 1),
            CFRange(location: max(cfRange.location - 1, 0), length: 1)
        ]
        for var candidate in fallbacks {
            guard let axRange = AXValueCreate(.cfRange, &candidate),
                  let rect = bounds(of: element, range: axRange),
                  rect.height >= 1
            else {
                continue
            }
            let normalizedRect = normalized(rect)
            return CGRect(
                x: normalizedRect.origin.x,
                y: normalizedRect.origin.y,
                width: max(normalizedRect.width, 1),
                height: normalizedRect.height
            )
        }
        return nil
    }

    private static func bounds(of element: AXUIElement, range: CFTypeRef) -> CGRect? {
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsRef
        ) == .success, let boundsRef else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
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
        return CGRect(origin: position, size: size)
    }

    private static func isUsableCaret(_ rect: CGRect) -> Bool {
        abs(rect.height) >= 1 && abs(rect.width) < 400
    }

    private static func normalized(_ rect: CGRect) -> CGRect {
        var result = rect
        if result.width < 0 {
            result.origin.x += result.width
            result.size.width = -result.width
        }
        if result.height < 0 {
            result.origin.y += result.height
            result.size.height = -result.height
        }
        return result
    }

    /// 辅助功能坐标系原点在主屏左上，AppKit 在左下。
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let primary else { return rect }
        let y = primary.frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }
}
