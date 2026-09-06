import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryPanelDismissTests: XCTestCase {
    func test_点在面板里不要关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        XCTAssertFalse(PanelDismissPolicy.shouldHide(click: KitPoint(x: 200, y: 200), keptFrames: [panel]))
    }

    func test_点在面板外要立刻关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        XCTAssertTrue(PanelDismissPolicy.shouldHide(click: KitPoint(x: 20, y: 20), keptFrames: [panel]))
    }

    func test_点在系统预览上不要关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        let preview = KitRect(x: 520, y: 220, width: 480, height: 360)
        XCTAssertFalse(PanelDismissPolicy.shouldHide(click: KitPoint(x: 700, y: 300), keptFrames: [panel, preview]))
    }

    func test_点在菜单栏本图标上不要关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        let statusItem = KitRect(x: 1200, y: 870, width: 28, height: 22)
        XCTAssertFalse(PanelDismissPolicy.shouldHide(click: KitPoint(x: 1210, y: 880), keptFrames: [panel, statusItem]))
        XCTAssertTrue(PanelDismissPolicy.shouldHide(click: KitPoint(x: 1100, y: 880), keptFrames: [panel, statusItem]))
    }
}
