import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HotkeyDefaultTests: XCTestCase {
    @MainActor
    func test_默认快捷键是CommandOptionV() {
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.displayName, "⌘⌥V")
    }
}
