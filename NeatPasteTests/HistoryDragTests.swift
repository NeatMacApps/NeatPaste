import AppKit
import MacKitCore
import MacKitLifecycle
import UniformTypeIdentifiers
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryDragTests: XCTestCase {
    func test_文本条可拖出字符串与txt文件() throws {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "Hello drag",
            sourceBundleID: nil,
            hasImage: false,
            types: ["public.utf8-plain-text"],
            payloads: ["public.utf8-plain-text": Data("Hello drag".utf8)]
        )
        let provider = try XCTUnwrap(HistoryDragProvider.provider(for: item) { _ in [:] })

        let stringExp = expectation(description: "string")
        var loadedString: String?
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            loadedString = (value as? NSString) as String?
            stringExp.fulfill()
        }
        wait(for: [stringExp], timeout: 5)
        XCTAssertEqual(loadedString, "Hello drag")

        let fileExp = expectation(description: "txt file")
        var loadedText: String?
        _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.plainText.identifier) { url, _ in
            if let url, let text = try? String(contentsOf: url, encoding: .utf8) {
                loadedText = text
            }
            fileExp.fulfill()
        }
        wait(for: [fileExp], timeout: 5)
        XCTAssertEqual(loadedText, "Hello drag")
        XCTAssertEqual(provider.suggestedName, "Hello drag.txt")
    }

    func test_内联图片拖出png数据与带扩展名文件() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.png": png]
        )
        let provider = try XCTUnwrap(HistoryDragProvider.provider(for: item) { _ in [:] })

        let dataExp = expectation(description: "png data")
        var loadedData: Data?
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            loadedData = data
            dataExp.fulfill()
        }
        wait(for: [dataExp], timeout: 5)
        XCTAssertEqual(loadedData, png)

        let fileExp = expectation(description: "png file")
        var fileURL: URL?
        var fileData: Data?
        _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
            fileURL = url
            if let url { fileData = try? Data(contentsOf: url) }
            fileExp.fulfill()
        }
        wait(for: [fileExp], timeout: 5)
        XCTAssertEqual(fileURL?.pathExtension, "png")
        XCTAssertEqual(fileData, png)
    }

    func test_外置图片经旁路拖出且不受stale文件地址影响() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let textFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-drag-stale-\(UUID().uuidString).txt")
        try "stale caption".write(to: textFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFile) }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-drag-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = UUID()
        let vault = PayloadVault(rootURL: dir)
        let spilled = try vault.spill(itemID: id, payloads: ["public.png": png])
        let materialize: @Sendable (UUID) async -> [String: Data] = { itemID in
            (try? vault.materialize(itemID: itemID, inline: [:], externalTypes: spilled.externalTypes)) ?? [:]
        }

        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            plainText: "stale caption",
            sourceBundleID: nil,
            hasImage: true,
            types: ["public.png"],
            payloads: ["public.file-url": Data(textFile.absoluteString.utf8)],
            externalPayloadTypes: spilled.externalTypes,
            payloadDirectoryURL: dir
        )
        let provider = try XCTUnwrap(HistoryDragProvider.provider(for: item, materialize: materialize))

        let fileExp = expectation(description: "external png file")
        var fileData: Data?
        var fileExtension: String?
        _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
            fileExtension = url?.pathExtension
            if let url { fileData = try? Data(contentsOf: url) }
            fileExp.fulfill()
        }
        wait(for: [fileExp], timeout: 5)
        XCTAssertEqual(fileExtension, "png")
        XCTAssertEqual(fileData, png)
    }

    func test_文件条直接拖出原文件() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("neatpaste-drag-src-\(UUID().uuidString).pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: file.lastPathComponent,
            sourceBundleID: nil,
            hasImage: false,
            types: ["public.file-url"],
            payloads: ["public.file-url": Data(file.absoluteString.utf8)]
        )
        let provider = try XCTUnwrap(HistoryDragProvider.provider(for: item) { _ in [:] })
        XCTAssertEqual(provider.suggestedName, file.lastPathComponent)
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier))
    }

    func test_无内容条不可拖() {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "",
            sourceBundleID: nil,
            hasImage: false,
            payloads: [:]
        )
        XCTAssertNil(HistoryDragProvider.provider(for: item) { _ in [:] })
    }
}
