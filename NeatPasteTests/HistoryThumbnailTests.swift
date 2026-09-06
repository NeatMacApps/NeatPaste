import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryThumbnailTests: XCTestCase {
    func test_能从外置旁路文件做出缩略图() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-thumb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let id = UUID()
        let vault = PayloadVault(rootURL: dir)
        _ = try vault.spill(itemID: id, payloads: ["public.png": png])

        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            plainText: "shot",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: [:],
            externalPayloadTypes: ["public.png"],
            payloadDirectoryURL: dir
        )
        let thumbnail = HistoryThumbnail.image(for: item)
        XCTAssertNotNil(thumbnail)
        XCTAssertGreaterThan(thumbnail?.size.width ?? 0, 0)
    }

    func test_能从png字节做出缩略图() {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "890D4B19-D55D-45F5-8549-775A75AFDD13_4.png",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.png": png]
        )
        let thumbnail = HistoryThumbnail.image(for: item)
        XCTAssertNotNil(thumbnail)
        XCTAssertGreaterThan(thumbnail?.size.width ?? 0, 0)
        XCTAssertGreaterThan(thumbnail?.size.height ?? 0, 0)
    }
}
