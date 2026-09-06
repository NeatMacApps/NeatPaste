import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

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
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
