import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class PanelAnchorTests: XCTestCase {
    func test_光标下方有空间时面板放在光标下面且左边界对齐() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 500, width: 2, height: 16)
        let size = NSSize(width: 400, height: 480)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(origin.y, caret.minY - size.height - PanelAnchor.caretGap, accuracy: 0.5)
        XCTAssertEqual(origin.x, caret.minX, accuracy: 0.5)
        XCTAssertLessThan(origin.y + size.height, caret.minY)
    }

    func test_光标贴右边时窗口往回夹仍完整可见() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 1400, y: 500, width: 2, height: 16)
        let size = NSSize(width: 400, height: 480)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(origin.x, visible.maxX - size.width - PanelAnchor.screenInset, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(origin.x, visible.minX + PanelAnchor.screenInset)
    }

    func test_光标贴左边时窗口不画出屏幕() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 2, y: 500, width: 2, height: 16)
        let size = NSSize(width: 400, height: 480)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(origin.x, visible.minX + PanelAnchor.screenInset, accuracy: 0.5)
    }

    func test_光标下方不够时改放到这一行上面() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 40, width: 2, height: 16)
        let size = NSSize(width: 400, height: 480)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(origin.y, caret.maxY + PanelAnchor.caretGap, accuracy: 0.5)
        XCTAssertEqual(origin.x, caret.minX, accuracy: 0.5)
        XCTAssertGreaterThan(origin.y, caret.maxY)
    }

    func test_短光标矩形也必须让开整行() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 508, width: 2, height: 2)
        let size = NSSize(width: 400, height: 480)
        let line = PanelAnchor.lineClearingRect(caret)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(line.height, PanelAnchor.minLineHeight, accuracy: 0.5)
        XCTAssertLessThanOrEqual(origin.y + size.height, line.minY - PanelAnchor.caretGap + 0.5)
        XCTAssertEqual(origin.x, caret.minX, accuracy: 0.5)
    }

    func test_大输入框收成靠近鼠标的小锚点() {
        let field = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let mouse = NSPoint(x: 300, y: 400)
        let compact = PanelAnchor.compactAnchor(from: field, mouse: mouse)
        XCTAssertEqual(compact.width, 2)
        XCTAssertEqual(compact.height, 16)
        XCTAssertEqual(compact.minX, 300, accuracy: 0.5)
        XCTAssertEqual(compact.minY, 392, accuracy: 0.5)
    }

    func test_小输入框保持原样() {
        let field = NSRect(x: 100, y: 200, width: 240, height: 22)
        let compact = PanelAnchor.compactAnchor(from: field, mouse: .zero)
        XCTAssertEqual(compact, field)
    }

    func test_光标下方时玻璃从面板左上角长出() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 500, width: 2, height: 16)
        let size = NSSize(width: 320, height: 432)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        let frame = NSRect(origin: origin, size: size)
        let placement = PanelAnchor.placement(frame: frame, preferredRect: caret)
        XCTAssertTrue(placement.pinsContentToTop)
        XCTAssertEqual(placement.seed.minX, frame.minX, accuracy: 0.5)
        XCTAssertEqual(placement.seed.maxY, frame.maxY, accuracy: 0.5)
        XCTAssertEqual(placement.seed.width, PanelAnchor.seedLength, accuracy: 0.5)
        XCTAssertTrue(frame.contains(NSPoint(x: placement.seed.midX, y: placement.seed.midY)))
    }

    func test_光标上方时玻璃从面板左下角长出() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 40, width: 2, height: 16)
        let size = NSSize(width: 320, height: 432)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        let frame = NSRect(origin: origin, size: size)
        let placement = PanelAnchor.placement(frame: frame, preferredRect: caret)
        XCTAssertFalse(placement.pinsContentToTop)
        XCTAssertEqual(placement.seed.minX, frame.minX, accuracy: 0.5)
        XCTAssertEqual(placement.seed.minY, frame.minY, accuracy: 0.5)
    }

    func test_进出场时长对高频操足够短且收起更快() {
        XCTAssertLessThanOrEqual(PanelMotion.appearDuration, 0.22)
        XCTAssertLessThan(PanelMotion.dismissDuration, PanelMotion.appearDuration)
        XCTAssertLessThan(PanelMotion.reducedDuration, PanelMotion.appearDuration)
    }
}
