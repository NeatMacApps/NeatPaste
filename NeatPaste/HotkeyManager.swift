import AppKit
@preconcurrency import Carbon
import SwiftUI

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    struct Shortcut: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32

        static let safeDefault = Shortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | optionKey)
        )

        /// 上一版出厂默认。仍停在这个组合的安装视为未自定义，随新出厂值一起改。
        static let retiredFactoryDefault = Shortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )

        var displayName: String {
            let modifierName = [
                (UInt32(cmdKey), "⌘"),
                (UInt32(optionKey), "⌥"),
                (UInt32(controlKey), "⌃"),
                (UInt32(shiftKey), "⇧")
            ]
            let prefix = modifierName.compactMap { modifiers & $0.0 != 0 ? $0.1 : nil }.joined()
            return prefix + Self.keyName(for: keyCode)
        }

        private static func keyName(for keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_ANSI_A: return "A"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_C: return "C"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_E: return "E"
            case kVK_ANSI_F: return "F"
            case kVK_ANSI_G: return "G"
            case kVK_ANSI_H: return "H"
            case kVK_ANSI_I: return "I"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_L: return "L"
            case kVK_ANSI_M: return "M"
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_O: return "O"
            case kVK_ANSI_P: return "P"
            case kVK_ANSI_Q: return "Q"
            case kVK_ANSI_R: return "R"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_T: return "T"
            case kVK_ANSI_U: return "U"
            case kVK_ANSI_V: return "V"
            case kVK_ANSI_W: return "W"
            case kVK_ANSI_X: return "X"
            case kVK_ANSI_Y: return "Y"
            case kVK_ANSI_Z: return "Z"
            case kVK_Space: return String(localized: "hotkey.key.space")
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Escape: return "⎋"
            default: return String(localized: "hotkey.key.unknown")
            }
        }
    }

    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var shortcut: Shortcut?
    @Published private(set) var isRecording = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var recordingMonitor: Any?
    private var nextHotKeyID: UInt32 = 1
    var onHotKey: (@MainActor () -> Void)?

    private init() {
        shortcut = Self.savedShortcut()
    }

    func register() {
        guard let shortcut else { return }
        register(shortcut, persist: false)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    func beginRecording() {
        stopRecording()
        lastErrorMessage = nil
        isRecording = true
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.finishRecording(event)
            return nil
        }
    }

    func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        isRecording = false
    }

    func clearShortcut() {
        stopRecording()
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        shortcut = nil
        AppPreferences.shared.clearHotkey()
        lastErrorMessage = nil
    }

    func restoreSafeDefault() {
        stopRecording()
        register(.safeDefault, persist: true)
    }

    private func finishRecording(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(from: event.modifierFlags))
        stopRecording()
        guard shortcut.modifiers != 0 else {
            lastErrorMessage = String(localized: "settings.hotkey.needModifier")
            return
        }
        guard !isReservedBySystem(shortcut) else {
            lastErrorMessage = String(localized: "settings.hotkey.reserved")
            return
        }
        register(shortcut, persist: true)
    }

    private func register(_ candidate: Shortcut, persist: Bool) {
        guard installEventHandler() else { return }
        if candidate == shortcut, hotKeyRef != nil { return }

        var newRef: EventHotKeyRef?
        // 签名 OSType 'NPST'
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E50_5354), id: nextHotKeyID)
        nextHotKeyID &+= 1
        let status = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            lastErrorMessage = String(localized: "settings.hotkey.taken")
            print("[NeatPaste] 注册全局快捷键失败：\(status)")
            return
        }

        if let oldRef = hotKeyRef { UnregisterEventHotKey(oldRef) }
        hotKeyRef = newRef
        shortcut = candidate
        lastErrorMessage = nil
        if persist {
            AppPreferences.shared.saveHotkey(keyCode: candidate.keyCode, modifiers: candidate.modifiers)
        }
    }

    private func installEventHandler() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.dispatchHotKey()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
        guard status == noErr else {
            lastErrorMessage = String(localized: "settings.hotkey.initFailed")
            print("[NeatPaste] 全局快捷键事件监听初始化失败：\(status)")
            return false
        }
        return true
    }

    nonisolated private func dispatchHotKey() {
        Task { @MainActor in self.onHotKey?() }
    }

    private func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func isReservedBySystem(_ shortcut: Shortcut) -> Bool {
        let command = UInt32(cmdKey)
        let systemKeys: Set<UInt32> = [
            UInt32(kVK_Space),
            UInt32(kVK_Tab),
            UInt32(kVK_ANSI_Q),
            UInt32(kVK_ANSI_W),
            UInt32(kVK_ANSI_H),
            UInt32(kVK_ANSI_M),
            UInt32(kVK_ANSI_Grave)
        ]
        return shortcut.modifiers == command && systemKeys.contains(shortcut.keyCode)
    }

    private static func savedShortcut() -> Shortcut? {
        migrateRetiredFactoryDefaultIfNeeded()
        guard AppPreferences.shared.isHotkeyEnabled() else { return nil }
        if let stored = AppPreferences.shared.storedHotkey() {
            return Shortcut(keyCode: stored.keyCode, modifiers: stored.modifiers)
        }
        return .safeDefault
    }

    /// 出厂默认从 ⌘⇧V 改为 ⌘⌥V：只改还停在旧出厂值的安装。
    private static func migrateRetiredFactoryDefaultIfNeeded() {
        let prefs = AppPreferences.shared
        guard prefs.hotkeyDefaultGeneration() < AppPreferences.currentHotkeyDefaultGeneration else { return }
        if let stored = prefs.storedHotkey() {
            let current = Shortcut(keyCode: stored.keyCode, modifiers: stored.modifiers)
            if current == .retiredFactoryDefault {
                prefs.saveHotkey(keyCode: Shortcut.safeDefault.keyCode, modifiers: Shortcut.safeDefault.modifiers)
            }
        }
        prefs.markHotkeyDefaultGeneration(AppPreferences.currentHotkeyDefaultGeneration)
    }
}
