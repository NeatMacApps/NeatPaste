import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryPayloadVaultTests: XCTestCase {
    func test_图片收入后外置且内存无整图() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let store = InMemoryHistoryStore(storageURL: url)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png", "NeXT TIFF v4.0 pasteboard type"],
                payloads: [
                    "public.png": png,
                    "NeXT TIFF v4.0 pasteboard type": png
                ],
                sourceBundleID: nil
            )
        )

        let items = await store.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].externalPayloadTypes.contains("public.png"))
        XCTAssertNil(items[0].payloads["public.png"])
        XCTAssertNotNil(items[0].preferredExternalImageURL())

        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains(png.base64EncodedString()), "瘦 JSON 不应再含整图 Base64")

        let materialized = await store.materializePayloads(id: items[0].id)
        XCTAssertEqual(materialized["public.png"], png)
        XCTAssertEqual(materialized["NeXT TIFF v4.0 pasteboard type"], png)

        let payloadsDir = dir.appendingPathComponent("payloads")
        let itemDir = payloadsDir.appendingPathComponent(items[0].id.uuidString)
        let files = try FileManager.default.contentsOfDirectory(atPath: itemDir.path)
        // manifest + 同一字节只一份 blob
        XCTAssertEqual(files.filter { $0 != "manifest.json" }.count, 1)
    }

    func test_相同图片外置后仍去重() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-dedupe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 200)

        let store = InMemoryHistoryStore(storageURL: url)
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

    func test_旧胖JSON启动时外置迁移() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let legacyID = UUID()
        let legacy: [[String: Any]] = [[
            "id": legacyID.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "plainText": "legacy-shot",
            "hasImage": true,
            "hasFilePromise": false,
            "types": ["public.png"],
            "payloads": ["public.png": png.base64EncodedString()]
        ]]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        try legacyData.write(to: url)

        let store = InMemoryHistoryStore(storageURL: url)
        let items = await store.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].plainText, "legacy-shot")
        XCTAssertTrue(items[0].externalPayloadTypes.contains("public.png"))
        XCTAssertNil(items[0].payloads["public.png"])

        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(rewritten.contains("inlinePayloads"))
        XCTAssertTrue(rewritten.contains("externalPayloadTypes"))
        XCTAssertFalse(rewritten.contains(png.base64EncodedString()))

        let thumb = HistoryThumbnail.image(for: items[0])
        XCTAssertNotNil(thumb)

        let preview = try QuickLookPreviewFile.makeURL(for: items[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: preview.path))
    }

    func test_过期清理会删旁路目录() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-expire-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        let png = Data(repeating: 9, count: 128)

        let store = InMemoryHistoryStore(storageURL: url)
        await store.ingest(
            PasteboardSnapshot(
                changeCount: 1,
                types: ["public.png"],
                payloads: ["public.png": png],
                sourceBundleID: nil
            )
        )
        let items = await store.items()
        let itemID = try XCTUnwrap(items.first?.id)
        let itemDir = dir.appendingPathComponent("payloads").appendingPathComponent(itemID.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemDir.path))

        await store.sweepExpired(olderThan: Date().addingTimeInterval(3600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDir.path))
        let remaining = await store.items()
        XCTAssertTrue(remaining.isEmpty)
    }
}
