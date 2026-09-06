import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryItemClickTests: XCTestCase {
    @MainActor
    func test_未选中再点只选中_已选中再点则粘贴() {
        XCTAssertEqual(HistoryItemClick.action(isAlreadySelected: false), .select)
        XCTAssertEqual(HistoryItemClick.action(isAlreadySelected: true), .paste)
    }

    @MainActor
    func test_点另一条只改选中不关面板() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        var hid = false
        model.onHide = { hid = true }
        await model.reload()
        let first = model.selectedID
        let second = model.visibleItems[1].id
        XCTAssertNotEqual(first, second)

        await model.handleItemClick(second)
        XCTAssertEqual(model.selectedID, second)
        XCTAssertFalse(hid)
        XCTAssertFalse(model.needsAccessibilityPrompt)
    }
}
