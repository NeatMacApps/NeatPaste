import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryRetentionTests: XCTestCase {
    func test_历史保留七天() {
        XCTAssertEqual(AppPreferences.historyLifetime, 7 * 24 * 3600)
        XCTAssertEqual(AppPreferences.clipboardPollInterval, 0.5, accuracy: 0.0001)
    }

    func test_面板默认尺寸是八成宽九成高() {
        XCTAssertEqual(AppPreferences.panelSize, NSSize(width: 320, height: 432))
    }

    @MainActor
    func test_菜单栏图标默认显示() {
        XCTAssertEqual(AppPreferences.Key.menuBarIconVisible, "menuBar.iconVisible")
        XCTAssertTrue(AppPreferences.menuBarIconVisibleDefault)
    }

    @MainActor
    func test_历史面板不可调整大小() {
        let panel = HistoryPanel(model: HistoryPanelModel(history: InMemoryHistoryStore()))
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.minSize, AppPreferences.panelSize)
        XCTAssertEqual(panel.maxSize, AppPreferences.panelSize)
    }
}
