import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class PanelAnchorTests: XCTestCase {
    func test_光标下方有空间时面板放在光标下面() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 400, y: 500, width: 2, height: 16)
        let size = NSSize(width: 400, height: 480)
        let origin = PanelAnchor.origin(for: size, on: visible, preferredRect: caret)
        XCTAssertEqual(origin.y, caret.minY - size.height - 12, accuracy: 0.5)
        XCTAssertEqual(origin.x, caret.midX - size.width / 2, accuracy: 0.5)
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
}
