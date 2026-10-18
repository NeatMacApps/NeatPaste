import AppKit
import XCTest
@testable import NeatPaste

final class IgnoredApplicationsTests: XCTestCase {
    @MainActor
    func testListEditsPersistAndRejectEmptyOrDuplicateIdentifiers() throws {
        let suite = "neatpaste.test.ignored.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.addIgnoredApplication(bundleID: "com.apple.TextEdit")
        preferences.addIgnoredApplication(bundleID: " com.apple.TextEdit ")
        preferences.addIgnoredApplication(bundleID: "  ")
        XCTAssertEqual(AppPreferences(defaults: defaults).ignoredAppBundleIDs, ["com.apple.TextEdit"])
        preferences.removeIgnoredApplication(bundleID: "com.apple.TextEdit")
        XCTAssertTrue(AppPreferences(defaults: defaults).ignoredAppBundleIDs.isEmpty)
    }

    @MainActor
    func testMonitorSkipsIgnoredCopyAndCapturesNextCopyAfterRemoval() async throws {
        let suite = "neatpaste.test.filter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let board = NSPasteboard(name: NSPasteboard.Name("neatpaste.test.filter.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = InMemoryHistoryStore()
        let monitor = ClipboardMonitor(
            history: history, pasteboard: board, preferences: preferences,
            sourceApplication: { "com.apple.TextEdit" }
        )
        preferences.addIgnoredApplication(bundleID: "com.apple.TextEdit")
        board.clearContents()
        XCTAssertTrue(board.setString("ignored-copy", forType: .string))
        await monitor.poll()
        let ignoredItems = await history.items()
        XCTAssertTrue(ignoredItems.isEmpty)

        preferences.removeIgnoredApplication(bundleID: "com.apple.TextEdit")
        await monitor.poll()
        let afterRemoval = await history.items()
        XCTAssertTrue(afterRemoval.isEmpty, "Removing an app must not backfill a skipped clipboard change.")

        board.clearContents()
        XCTAssertTrue(board.setString("allowed-copy", forType: .string))
        await monitor.poll()
        let allowedItems = await history.items()
        XCTAssertEqual(allowedItems.map(\.plainText), ["allowed-copy"])
        XCTAssertEqual(allowedItems.first?.sourceBundleID, "com.apple.TextEdit")
        preferences.addIgnoredApplication(bundleID: "com.apple.TextEdit")
        let existingItems = await history.items()
        XCTAssertEqual(existingItems.map(\.plainText), ["allowed-copy"], "Adding an app must preserve existing history.")
    }
}
