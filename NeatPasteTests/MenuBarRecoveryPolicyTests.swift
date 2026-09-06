import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class MenuBarRecoveryPolicyTests: XCTestCase {
    func test_图标隐藏时再次打开必须出示恢复窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(iconVisible: false, isReopenOrLaunch: true),
            .showRecoveryWindow
        )
        XCTAssertTrue(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false))
    }

    func test_登录项拉起即使图标隐藏也不出示恢复窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(
                iconVisible: false,
                isReopenOrLaunch: true,
                isLoginLaunch: true
            ),
            .none
        )
        XCTAssertFalse(
            MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false, isLoginLaunch: true)
        )
    }

    func test_图标可见时再次打开不要用恢复窗顶替() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(iconVisible: true, isReopenOrLaunch: true),
            .none
        )
        XCTAssertFalse(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: true))
    }

    func test_待批准不能当成开机自启已打开() {
        XCTAssertTrue(LaunchAtLoginStatus.on.isEffectivelyEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.needsApproval.isEffectivelyEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.off.isEffectivelyEnabled)
    }
}
