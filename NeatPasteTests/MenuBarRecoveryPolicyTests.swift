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

    func test_图标可见且未开主入口防呆时再次打开不要弹窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(iconVisible: true, isReopenOrLaunch: true),
            .none
        )
        XCTAssertFalse(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: true))
    }

    func test_菜单栏主入口时间窗内图标可见也须出窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(
                iconVisible: true,
                isReopenOrLaunch: true,
                menubarIsPrimaryEntry: true,
                secondsSinceReady: 15
            ),
            .showRecoveryWindow
        )
    }

    func test_菜单栏主入口超时后图标可见可不出窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(
                iconVisible: true,
                isReopenOrLaunch: true,
                menubarIsPrimaryEntry: true,
                secondsSinceReady: 61
            ),
            .none
        )
    }

    func test_菜单栏主入口超时后图标隐藏仍须出窗() {
        XCTAssertEqual(
            MenuBarReopenPolicy.presentation(
                iconVisible: false,
                isReopenOrLaunch: true,
                menubarIsPrimaryEntry: true,
                secondsSinceReady: 120
            ),
            .showRecoveryWindow
        )
    }

    func test_待批准不能当成开机自启已打开() {
        XCTAssertTrue(LaunchAtLoginStatus.on.isEffectivelyEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.needsApproval.isEffectivelyEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.off.isEffectivelyEnabled)
    }
}
