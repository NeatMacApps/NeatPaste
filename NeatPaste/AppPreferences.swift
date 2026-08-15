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
    }

    /// 历史只保留 7 天。
    nonisolated static let historyLifetime: TimeInterval = 7 * 24 * 3600

    /// 剪贴板变化探测间隔。
    nonisolated static let clipboardPollInterval: TimeInterval = 0.5

    nonisolated static let rowHeight: CGFloat = 44
    nonisolated static let panelSize = NSSize(width: 680, height: 440)

    var ignoredAppBundleIDs: [String] {
        didSet {
            UserDefaults.standard.set(ignoredAppBundleIDs, forKey: Key.ignoredAppBundleIDs)
        }
    }

    private init() {
        ignoredAppBundleIDs = UserDefaults.standard.stringArray(forKey: Key.ignoredAppBundleIDs) ?? []
        UserDefaults.standard.register(defaults: [
            Key.hotkeyEnabled: true
        ])
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
}
