import AppKit
import Foundation
@preconcurrency import Carbon
import Observation

/// 全部偏好键与产品常量的唯一来源。禁止在其它文件写字符串键。
@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    enum Key {
        static let hotkeyKeyCode = "hotkey.keyCode"
        static let hotkeyModifiers = "hotkey.modifiers"
        static let hotkeyEnabled = "hotkey.enabled"
        static let ignoredAppBundleIDs = "ignore.bundleIDs"
        static let hotkeyDefaultGeneration = "hotkey.defaultGeneration"
        static let menuBarIconVisible = "menuBar.iconVisible"
    }

    /// 菜单栏图标出厂默认显示。
    nonisolated static let menuBarIconVisibleDefault = true

    /// 出厂默认快捷键代数。从 1（⌘⇧V）升到 2（⌘⌥V）时，只覆盖仍停在旧出厂值的安装，不覆盖用户改过的组合。
    nonisolated static let currentHotkeyDefaultGeneration = 2

    /// 历史只保留 7 天。
    nonisolated static let historyLifetime: TimeInterval = 7 * 24 * 3600

    /// 剪贴板变化探测间隔。
    nonisolated static let clipboardPollInterval: TimeInterval = 0.5

    nonisolated static let rowHeight: CGFloat = 44
    nonisolated static let panelSize = NSSize(width: 320, height: 432)
    nonisolated static let panelCornerRadius: CGFloat = 20
    /// 系统预览的默认尺寸：小窗，不要跟着文本把屏幕占满。
    nonisolated static let quickLookSize = NSSize(width: 480, height: 360)
    nonisolated static let quickLookMinSize = NSSize(width: 320, height: 240)
    nonisolated static let quickLookMaxSize = NSSize(width: 560, height: 420)

    var ignoredAppBundleIDs: [String] {
        didSet {
            UserDefaults.standard.set(ignoredAppBundleIDs, forKey: Key.ignoredAppBundleIDs)
        }
    }

    /// 菜单栏图标是否显示。缺省为显示；用键是否存在判断，避免把空当成关。
    var isMenuBarIconVisible: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarIconVisible, forKey: Key.menuBarIconVisible)
        }
    }

    private init() {
        ignoredAppBundleIDs = UserDefaults.standard.stringArray(forKey: Key.ignoredAppBundleIDs) ?? []
        UserDefaults.standard.register(defaults: [
            Key.hotkeyEnabled: true,
            Key.menuBarIconVisible: Self.menuBarIconVisibleDefault
        ])
        if UserDefaults.standard.object(forKey: Key.menuBarIconVisible) == nil {
            isMenuBarIconVisible = Self.menuBarIconVisibleDefault
        } else {
            isMenuBarIconVisible = UserDefaults.standard.bool(forKey: Key.menuBarIconVisible)
        }
    }

    /// 显隐菜单栏图标。关掉时必须出示恢复窗口，不能只把图标拿掉。
    func setMenuBarIconVisible(_ visible: Bool) {
        isMenuBarIconVisible = visible
        AppDelegate.shared?.applyMenuBarIconVisibility()
        if !visible {
            AppDelegate.shared?.showRecoveryWindow()
        }
    }

    func saveHotkey(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: Key.hotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers), forKey: Key.hotkeyModifiers)
        UserDefaults.standard.set(true, forKey: Key.hotkeyEnabled)
    }

    func clearHotkey() {
        UserDefaults.standard.set(false, forKey: Key.hotkeyEnabled)
    }

    func isHotkeyEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: Key.hotkeyEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Key.hotkeyEnabled)
    }

    func storedHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard isHotkeyEnabled() else { return nil }
        guard UserDefaults.standard.object(forKey: Key.hotkeyKeyCode) != nil else { return nil }
        return (
            UInt32(UserDefaults.standard.integer(forKey: Key.hotkeyKeyCode)),
            UInt32(UserDefaults.standard.integer(forKey: Key.hotkeyModifiers))
        )
    }

    func hotkeyDefaultGeneration() -> Int {
        UserDefaults.standard.integer(forKey: Key.hotkeyDefaultGeneration)
    }

    func markHotkeyDefaultGeneration(_ value: Int) {
        UserDefaults.standard.set(value, forKey: Key.hotkeyDefaultGeneration)
    }
}
