import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistorySearchTests: XCTestCase {
    func test_假数据筛选不区分大小写() async {
        let store = InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems())
        let all = await store.items()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.plainText.contains("NeatPaste"), true)
        XCTAssertTrue(all.contains { $0.hasImage })

        let english = await store.search("neatpaste")
        XCTAssertEqual(english.count, 1)

        let chinese = await store.search("中文")
        XCTAssertEqual(chinese.count, 1)

        let empty = await store.search("   ")
        XCTAssertEqual(empty.count, 3)
    }

    func test_包含匹配是纯函数() {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "Hello NeatPaste",
            sourceBundleID: nil,
            hasImage: false
        )
        XCTAssertTrue(HistorySearch.matches(item, query: "neat"))
        XCTAssertFalse(HistorySearch.matches(item, query: "missing"))
    }
}
