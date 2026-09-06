import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryDeleteTests: XCTestCase {
    @MainActor
    func test_删除当前条后选中落到同位置下一条且不关面板() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        var hid = false
        model.onHide = { hid = true }
        await model.reload()
        XCTAssertEqual(model.visibleItems.count, 3)
        let first = model.visibleItems[0].id
        let second = model.visibleItems[1].id

        await model.deleteItem(first)
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedID, second)
        XCTAssertFalse(hid)
        let remaining = await store.items()
        XCTAssertFalse(remaining.contains { $0.id == first })
    }

    @MainActor
    func test_删除最后一条后选中落到上一条() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        await model.reload()
        let last = model.visibleItems[2].id
        let previous = model.visibleItems[1].id
        model.select(last)

        await model.deleteItem(last)
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedID, previous)
    }

    @MainActor
    func test_删除非选中条时保留原选中() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        await model.reload()
        let first = model.visibleItems[0].id
        let third = model.visibleItems[2].id

        await model.deleteItem(third)
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedID, first)
    }
}
