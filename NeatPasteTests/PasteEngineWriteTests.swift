import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class PasteEngineWriteTests: XCTestCase {
    @MainActor
    func test_文本和文件地址一次写入后都还在() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("neatpaste-writeback-\(UUID().uuidString).txt")
        try "from disk".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = "hello-with-file-\(UUID().uuidString)"
        let record = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: text,
            sourceBundleID: nil,
            hasImage: false,
            types: ["public.utf8-plain-text", NSPasteboard.PasteboardType.fileURL.rawValue],
            payloads: [
                "public.utf8-plain-text": Data(text.utf8),
                NSPasteboard.PasteboardType.fileURL.rawValue: Data(file.absoluteString.utf8)
            ]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.write.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteEngine.write(record, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), text)
        let fileURL = pasteboard.string(forType: .fileURL)
            ?? pasteboard.pasteboardItems?.compactMap { $0.string(forType: .fileURL) }.first
        XCTAssertTrue(
            fileURL?.contains(file.lastPathComponent) == true,
            "写回后应仍带文件地址，实际=\(fileURL ?? "nil")"
        )
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType(PasteboardCapture.internalType)))
    }

    @MainActor
    func test_写回返回的变化计数与当前板一致() {
        let text = "change-count-\(UUID().uuidString)"
        let record = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: text,
            sourceBundleID: nil,
            hasImage: false,
            types: ["public.utf8-plain-text"],
            payloads: ["public.utf8-plain-text": Data(text.utf8)]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.write.count.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let written = PasteEngine.write(record, to: pasteboard)
        XCTAssertEqual(written, pasteboard.changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }
}
