import AppKit
@preconcurrency import Carbon
import Foundation

enum PasteOutcome: Equatable, Sendable {
    case autoPasted
    case copiedOnly
}

@MainActor
enum PasteEngine {
    /// 把条目写入系统剪贴板；若已授权辅助功能则合成 ⌘V。调用方必须先在自动粘贴路径里关掉面板。
    static func paste(record: HistoryItem) async -> PasteOutcome {
        writeToPasteboard(record)
        print("[NeatPaste] 已将条目写入系统剪贴板：\(record.plainText.prefix(40))")

        guard AccessibilityPermission.isTrusted else {
            print("[NeatPaste] 未获得辅助功能授权，仅写入剪贴板，不合成粘贴键")
            return .copiedOnly
        }

        await Task.yield()
        synthesizeCommandV()
        print("[NeatPaste] 已合成粘贴键")
        return .autoPasted
    }

    private static func writeToPasteboard(_ record: HistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.plainText, forType: .string)
    }

    private static func synthesizeCommandV() {
        let commandFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        let vCode = CGKeyCode(kVK_ANSI_V)
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
        keyDown?.flags = commandFlag
        keyUp?.flags = commandFlag
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
