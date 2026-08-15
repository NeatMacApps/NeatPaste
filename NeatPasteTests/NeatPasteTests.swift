import AppKit
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HotkeyDefaultTests: XCTestCase {
    @MainActor
    func test_默认快捷键是CommandShiftV() {
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(HotkeyManager.Shortcut.safeDefault.modifiers, UInt32(cmdKey | shiftKey))
    }
}

final class HistoryRetentionTests: XCTestCase {
    func test_历史保留七天() {
        XCTAssertEqual(AppPreferences.historyLifetime, 7 * 24 * 3600)
        XCTAssertEqual(AppPreferences.clipboardPollInterval, 0.5, accuracy: 0.0001)
    }
}

final class HistorySearchTests: XCTestCase {
    func test_假数据筛选不区分大小写() async {
        let store = InMemoryHistoryStore()
        let all = await store.items()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.plainText.contains("NeatPaste"), true)
        XCTAssertTrue(all.contains { $0.hasImage })

        let english = await store.search("neatpaste")
        XCTAssertEqual(english.count, 1)

        let chinese = await store.search("中文")
        XCTAssertEqual(chinese.count, 1)

        let empty = await store.search("   ")
        XCTAssertEqual(empty.count, 3)
    }

    func test_包含匹配是纯函数() {
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: "Hello NeatPaste",
            sourceBundleID: nil,
            hasImage: false
        )
        XCTAssertTrue(HistorySearch.matches(item, query: "neat"))
        XCTAssertFalse(HistorySearch.matches(item, query: "missing"))
    }
}

final class AutofillHeuristicGuardTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NeatPasteTests.autofill.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_注册默认值关闭AutoFill启发式() {
        XCTAssertEqual(
            AutofillHeuristicGuard.registeredDefaults()[AutofillHeuristicGuard.defaultsKey],
            false
        )
        AutofillHeuristicGuard.install(defaults: defaults)
        XCTAssertEqual(defaults.object(forKey: AutofillHeuristicGuard.defaultsKey) as? Bool, false)
    }
}

final class AppDelegateTests: XCTestCase {
    @MainActor
    func test_用户主动退出会放行并发出终止请求() {
        let delegate = AppDelegate()
        var didRequestTermination = false
        delegate.requestTermination {
            didRequestTermination = true
        }
        XCTAssertTrue(didRequestTermination)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
    }
}
