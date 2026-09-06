import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryTextTests: XCTestCase {
    func test_从UTF8载荷抽出纯文本() {
        let text = HistoryText.plainText(from: [
            "public.utf8-plain-text": Data("hello".utf8)
        ])
        XCTAssertEqual(text, "hello")
    }

    func test_图片临时文件名不当标题() {
        let uuidName = "890D4B19-D55D-45F5-8549-775A75AFDD13_4.png"
        XCTAssertTrue(HistoryText.isMachineGeneratedName(uuidName))
        XCTAssertEqual(
            HistoryText.listTitle(plainText: uuidName, hasImage: true),
            String(localized: "panel.image.placeholder")
        )
        XCTAssertEqual(
            HistoryText.listTitle(
                plainText: "file:///var/folders/xx/T/\(uuidName)",
                hasImage: true
            ),
            String(localized: "panel.image.placeholder")
        )
    }

    func test_真人能认的截图文件名要保留() {
        let name = "Screenshot 2026-08-15 at 17.12.00.png"
        XCTAssertFalse(HistoryText.isMachineGeneratedName(name))
        XCTAssertEqual(HistoryText.listTitle(plainText: name, hasImage: true), name)
    }

    func test_普通文本标题保持原样() {
        XCTAssertEqual(HistoryText.listTitle(plainText: "hello", hasImage: false), "hello")
    }
}
