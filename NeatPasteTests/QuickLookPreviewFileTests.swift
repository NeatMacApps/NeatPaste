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

    func test_预览窗默认尺寸保持小窗() {
        XCTAssertEqual(AppPreferences.quickLookSize, NSSize(width: 480, height: 360))
        XCTAssertLessThanOrEqual(AppPreferences.quickLookMaxSize.width, 560)
        XCTAssertLessThanOrEqual(AppPreferences.quickLookMaxSize.height, 420)
        XCTAssertGreaterThan(AppPreferences.quickLookMaxSize.width, AppPreferences.quickLookSize.width)
        XCTAssertGreaterThan(AppPreferences.quickLookMaxSize.height, AppPreferences.quickLookSize.height)
    }
}
