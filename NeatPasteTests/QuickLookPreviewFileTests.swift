import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class QuickLookPreviewFileTests: XCTestCase {
    func test_纯文本落成txt() throws {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "Hello Quick Look",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.utf8-plain-text": Data("Hello Quick Look".utf8)]
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertEqual(url.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Hello Quick Look")
    }

    func test_图片优先用png字节() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "screenshot",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.png": png]
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url), png)
    }

    func test_存在的本地文件直接用原路径() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-ql-source.txt")
        try "from disk".write(to: file, atomically: true, encoding: .utf8)
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "from disk",
            sourceBundleID: nil,
            hasImage: false,
            payloads: ["public.file-url": Data(file.absoluteString.utf8)]
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertEqual(url.standardizedFileURL, file.standardizedFileURL)
    }

    func test_图片条目旁路优先于仍存在的非图片fileurl() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let textFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-ql-stale-\(UUID().uuidString).txt")
        try "stale caption".write(to: textFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFile) }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-ql-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = UUID()
        let vault = PayloadVault(rootURL: dir)
        _ = try vault.spill(itemID: id, payloads: ["public.png": png])

        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            plainText: "stale caption",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.file-url": Data(textFile.absoluteString.utf8)],
            externalPayloadTypes: ["public.png"],
            payloadDirectoryURL: dir
        )

        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertNotEqual(url.standardizedFileURL, textFile.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: url), png)
        // 旁路 blob 无扩展名，预览必须落在带图片扩展名的临时文件，否则 Quick Look 会当文本打开。
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.path.contains("NeatPasteQuickLook"))
    }

    func test_旁路图片预览必须带扩展名() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-ql-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let vault = PayloadVault(rootURL: dir)
        _ = try vault.spill(itemID: id, payloads: ["public.png": png])
        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            plainText: "",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: [:],
            externalPayloadTypes: ["public.png"],
            payloadDirectoryURL: dir
        )
        let url = try QuickLookPreviewFile.makeURL(for: item)
        XCTAssertFalse(url.pathExtension.isEmpty, "扩展名为空会被 Quick Look 当文本")
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url), png)
    }

    func test_预览窗默认尺寸保持小窗() {
        XCTAssertEqual(AppPreferences.quickLookSize, NSSize(width: 480, height: 360))
        XCTAssertLessThanOrEqual(AppPreferences.quickLookMaxSize.width, 560)
        XCTAssertLessThanOrEqual(AppPreferences.quickLookMaxSize.height, 420)
        XCTAssertGreaterThan(AppPreferences.quickLookMaxSize.width, AppPreferences.quickLookSize.width)
        XCTAssertGreaterThan(AppPreferences.quickLookMaxSize.height, AppPreferences.quickLookSize.height)
    }
}
