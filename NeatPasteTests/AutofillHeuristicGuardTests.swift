import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

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
