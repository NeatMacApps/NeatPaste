import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistorySelectionTests: XCTestCase {
    @MainActor
    func test_连续下移会走到后面的条目() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let model = HistoryPanelModel(history: store)
        await model.reload()
        XCTAssertEqual(model.visibleItems.count, 3)

        let first = model.selectedID
        model.moveSelection(1)
        let second = model.selectedID
        XCTAssertNotEqual(first, second)
        model.moveSelection(1)
        XCTAssertNotEqual(model.selectedID, second)
        XCTAssertNotEqual(model.selectedID, first)
    }
}
