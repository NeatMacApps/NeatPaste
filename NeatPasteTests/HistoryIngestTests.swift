import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryIngestTests: XCTestCase {
    func test_空仓库默认没有假数据() async {
        let store = InMemoryHistoryStore()
        let all = await store.items()
        XCTAssertEqual(all.count, 0)
    }

    func test_收入快照后出现在列表最前() async {
        let store = InMemoryHistoryStore()
        let payload = Data("unique-clipboard-token-α".utf8)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 42,
                types: ["public.utf8-plain-text"],
                payloads: ["public.utf8-plain-text": payload],
                sourceBundleID: "com.apple.TextEdit"
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.plainText, "unique-clipboard-token-α")
        XCTAssertEqual(all.first?.payloads["public.utf8-plain-text"], payload)
    }

    func test_过期记录会被清掉() async {
        let old = HistoryItem(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-8 * 24 * 3600),
            plainText: "too old",
            sourceBundleID: nil,
            hasImage: false
        )
        let store = InMemoryHistoryStore(records: [old])
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.utf8-plain-text"],
                payloads: ["public.utf8-plain-text": Data("fresh".utf8)],
                sourceBundleID: nil
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.map(\.plainText), ["fresh"])
    }

    func test_相同文本再次复制只留一条并顶到最上() async {
        let store = InMemoryHistoryStore()
        await store.ingest(textSnapshot("alpha", changeCount: 1))
        await store.ingest(textSnapshot("beta", changeCount: 2))
        await store.ingest(textSnapshot("alpha", changeCount: 3))
        let all = await store.items()
        XCTAssertEqual(all.map(\.plainText), ["alpha", "beta"])
    }

    func test_相同图片再次复制只留一条() async {
        let store = InMemoryHistoryStore()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png"],
                payloads: ["public.png": bytes],
                sourceBundleID: nil
            )
        )
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 2,
                types: ["public.png", "public.utf8-plain-text"],
                payloads: [
                    "public.png": bytes,
                    "public.utf8-plain-text": Data("screenshot".utf8)
                ],
                sourceBundleID: "com.apple.screencapture"
            )
        )
        let all = await store.items()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].hasImage)
    }

    func test_落盘后新仓库能读回未过期记录() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = InMemoryHistoryStore(storageURL: url)
        await first.ingest(textSnapshot("survive-restart", changeCount: 1))
        let second = InMemoryHistoryStore(storageURL: url)
        let all = await second.items()
        XCTAssertEqual(all.map(\.plainText), ["survive-restart"])
        XCTAssertEqual(all.first?.payloads["public.utf8-plain-text"], Data("survive-restart".utf8))
    }

    func test_过期记录读盘时会被丢掉() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let old = HistoryItem(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-8 * 24 * 3600),
            plainText: "expired-on-disk",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.utf8-plain-text": Data("expired-on-disk".utf8)]
        )
        let fresh = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "still-valid",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.utf8-plain-text": Data("still-valid".utf8)]
        )
        _ = InMemoryHistoryStore(records: [old, fresh], storageURL: url)
        let reloaded = InMemoryHistoryStore(storageURL: url)
        let all = await reloaded.items()
        XCTAssertEqual(all.map(\.plainText), ["still-valid"])
    }

    private func textSnapshot(_ text: String, changeCount: Int) -> PasteboardSnapshot {
        PasteboardSnapshot(
            changeCount: changeCount,
            types: ["public.utf8-plain-text"],
            payloads: ["public.utf8-plain-text": Data(text.utf8)],
            sourceBundleID: nil
        )
    }
}
