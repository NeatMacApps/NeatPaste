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
        static let selectedSettingsPane = "settings.selectedPane"
    }

    /// 菜单栏图标出厂默认显示。
    nonisolated static let menuBarIconVisibleDefault = true
    nonisolated static let selectedSettingsPaneDefault = "general"

    private let defaults: UserDefaults

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

    private(set) var ignoredAppBundleIDs: [String] {
        didSet {
            defaults.set(ignoredAppBundleIDs, forKey: Key.ignoredAppBundleIDs)
        }
    }

    /// 菜单栏图标是否显示。缺省为显示；用键是否存在判断，避免把空当成关。
    var isMenuBarIconVisible: Bool {
        didSet {
            defaults.set(isMenuBarIconVisible, forKey: Key.menuBarIconVisible)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ignoredAppBundleIDs = defaults.stringArray(forKey: Key.ignoredAppBundleIDs) ?? []
        defaults.register(defaults: [
            Key.hotkeyEnabled: true,
            Key.menuBarIconVisible: Self.menuBarIconVisibleDefault
        ])
        if defaults.object(forKey: Key.menuBarIconVisible) == nil {
            isMenuBarIconVisible = Self.menuBarIconVisibleDefault
        } else {
            isMenuBarIconVisible = defaults.bool(forKey: Key.menuBarIconVisible)
        }
    }

    func addIgnoredApplication(bundleID: String) {
        let identifier = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !ignoredAppBundleIDs.contains(identifier) else { return }
        ignoredAppBundleIDs.append(identifier)
    }

    func removeIgnoredApplication(bundleID: String) {
        ignoredAppBundleIDs.removeAll { $0 == bundleID }
    }

    /// 显隐菜单栏图标。点隐藏时静默，不弹恢复窗；再次打开应用或「打开主窗口」才出示。
    func setMenuBarIconVisible(_ visible: Bool) {
        isMenuBarIconVisible = visible
        AppDelegate.shared?.applyMenuBarIconVisibility()
    }

    func saveHotkey(keyCode: UInt32, modifiers: UInt32) {
        defaults.set(Int(keyCode), forKey: Key.hotkeyKeyCode)
        defaults.set(Int(modifiers), forKey: Key.hotkeyModifiers)
        defaults.set(true, forKey: Key.hotkeyEnabled)
    }

    func clearHotkey() {
        defaults.set(false, forKey: Key.hotkeyEnabled)
    }

    func isHotkeyEnabled() -> Bool {
        if defaults.object(forKey: Key.hotkeyEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: Key.hotkeyEnabled)
    }

    func storedHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard isHotkeyEnabled() else { return nil }
        guard defaults.object(forKey: Key.hotkeyKeyCode) != nil else { return nil }
        return (
            UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
            UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
        )
    }

    func hotkeyDefaultGeneration() -> Int {
        defaults.integer(forKey: Key.hotkeyDefaultGeneration)
    }

    func markHotkeyDefaultGeneration(_ value: Int) {
        defaults.set(value, forKey: Key.hotkeyDefaultGeneration)
    }
}
