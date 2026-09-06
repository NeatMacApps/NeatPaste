import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class PasteboardCaptureTests: XCTestCase {
    func test_密码管理器标记不收录() {
        let decision = PasteboardCapture.decide(
            types: ["public.utf8-plain-text", PasteboardCapture.concealedType],
            sourceBundleID: "com.apple.Safari",
            ignoredApps: []
        )
        XCTAssertEqual(decision, .skipSensitive)
    }

    func test_瞬时内容不收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: [PasteboardCapture.transientType, "public.utf8-plain-text"],
                sourceBundleID: nil,
                ignoredApps: []
            ),
            .skipSensitive
        )
    }

    func test_本应用写回不收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: ["public.utf8-plain-text", PasteboardCapture.internalType],
                sourceBundleID: nil,
                ignoredApps: []
            ),
            .skipOwnWrite
        )
    }

    func test_忽略名单中的应用不收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: ["public.utf8-plain-text"],
                sourceBundleID: "com.bank.app",
                ignoredApps: ["com.bank.app"]
            ),
            .skipIgnoredApp
        )
    }

    func test_普通文本会收录() {
        XCTAssertEqual(
            PasteboardCapture.decide(
                types: ["public.utf8-plain-text"],
                sourceBundleID: "com.apple.TextEdit",
                ignoredApps: []
            ),
            .capture
        )
    }

    func test_不读取Word链接源类型() {
        XCTAssertTrue(PasteboardCapture.isUnsafeToRead(PasteboardCapture.microsoftLinkSource))
        XCTAssertTrue(PasteboardCapture.isUnsafeToRead("com.microsoft.ole.source.doc"))
        XCTAssertFalse(PasteboardCapture.isUnsafeToRead("public.utf8-plain-text"))
    }

    func test_内容还没装上时不要把变化计数往前推() {
        XCTAssertFalse(PasteboardCapture.shouldAdvanceChangeCount(decision: .capture, didCapture: false))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .capture, didCapture: true))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .skipSensitive, didCapture: false))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .skipOwnWrite, didCapture: false))
        XCTAssertTrue(PasteboardCapture.shouldAdvanceChangeCount(decision: .skipIgnoredApp, didCapture: false))
    }

    func test_收录过程中变化计数漂移则不能提交() {
        XCTAssertTrue(ClipboardMonitor.isChangeCountStable(observed: 7, current: 7))
        XCTAssertFalse(ClipboardMonitor.isChangeCountStable(observed: 7, current: 8))
    }

    @MainActor
    func test_独立剪贴板能从整板字符串读出快照() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.string.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let token = "neatpaste-board-string-\(UUID().uuidString)"
        XCTAssertTrue(pasteboard.setString(token, forType: .string))

        let snapshot = PasteboardCapture.snapshot(from: pasteboard, sourceBundleID: nil, ignoredApps: [])
        XCTAssertEqual(
            snapshot?.payloads["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) },
            token
        )
    }

    @MainActor
    func test_条目只有字符串没有字节时仍能读出() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.item-string.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let token = "neatpaste-item-string-\(UUID().uuidString)"
        let item = NSPasteboardItem()
        item.setString(token, forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let snapshot = PasteboardCapture.snapshot(from: pasteboard, sourceBundleID: nil, ignoredApps: [])
        XCTAssertEqual(
            snapshot?.payloads["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) },
            token
        )
    }
}
