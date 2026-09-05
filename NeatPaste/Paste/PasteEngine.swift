import AppKit
@preconcurrency import Carbon
import Foundation

enum PasteOutcome: Equatable, Sendable {
    case autoPasted
    case copiedOnly
}

@MainActor
enum PasteEngine {
    /// 把条目按原始类型写回系统剪贴板；若已授权辅助功能则合成 ⌘V。调用方必须先在自动粘贴路径里关掉面板。
    static func paste(record: HistoryItem, payloads: [String: Data]? = nil) async -> PasteOutcome {
        var writtenChangeCount = write(record, payloads: payloads ?? record.payloads, to: NSPasteboard.general)
        print("[NeatPaste] 已将条目写入系统剪贴板：\(record.plainText.prefix(40))")

        guard AccessibilityPermission.isTrusted else {
            print("[NeatPaste] 未获得辅助功能授权，仅写入剪贴板，不合成粘贴键")
            return .copiedOnly
        }

        await Task.yield()
        // 写回后若板被别人冲掉，禁止合成 ⌘V，否则会贴错内容；先再写一次，仍不稳则只保留「已复制」。
        if NSPasteboard.general.changeCount != writtenChangeCount {
            print("[NeatPaste] 写回后剪贴板已被改写，重新写回后再粘贴")
            writtenChangeCount = write(record, payloads: payloads ?? record.payloads, to: NSPasteboard.general)
        }
        guard NSPasteboard.general.changeCount == writtenChangeCount else {
            print("[NeatPaste] 剪贴板仍不稳定，取消合成粘贴键，避免贴错")
            return .copiedOnly
        }

        guard synthesizeCommandV() else {
            print("[NeatPaste] 合成粘贴键失败，仅写入剪贴板")
            return .copiedOnly
        }
        print("[NeatPaste] 已合成粘贴键")
        return .autoPasted
    }

    /// 写回条目并打内部标记；返回写完后的 changeCount（general 板上还会通知监听跳过本条写回）。
    @discardableResult
    static func write(_ record: HistoryItem, payloads: [String: Data]? = nil, to pasteboard: NSPasteboard) -> Int {
        let resolved = payloads ?? record.payloads
        pasteboard.clearContents()

        let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
        let fileDatas: [Data] = record.types.compactMap { type in
            guard type == fileURLType else { return nil }
            return resolved[type]
        }
        let otherTypes = record.types.filter { type in
            type != fileURLType
                && !PasteboardCapture.isFilePromise(type)
                && !PasteboardCapture.isUnsafeToRead(type)
                && resolved[type] != nil
        }

        if fileDatas.isEmpty {
            var didWrite = false
            for type in otherTypes {
                if let data = resolved[type] {
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
                    didWrite = true
                }
            }
            if !didWrite, !record.plainText.isEmpty, resolved.isEmpty {
                pasteboard.setString(record.plainText, forType: .string)
            }
        } else {
            // writeObjects 会整板替换，所以文本/图片必须和文件地址放在同一批条目里一次写入。
            var items: [NSPasteboardItem] = []
            let first = NSPasteboardItem()
            for type in otherTypes {
                if let data = resolved[type] {
                    first.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            }
            first.setData(fileDatas[0], forType: .fileURL)
            items.append(first)
            for extra in fileDatas.dropFirst() {
                let item = NSPasteboardItem()
                item.setData(extra, forType: .fileURL)
                items.append(item)
            }
            pasteboard.writeObjects(items)
        }

        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardCapture.internalType))
        let changeCount = pasteboard.changeCount
        if pasteboard.name == NSPasteboard.Name.general {
            AppDelegate.shared?.clipboardMonitor.noteOwnWrite(changeCount: changeCount)
        }
        return changeCount
    }

    /// 合成 ⌘V；事件创建失败时返回 false，调用方不得当成已自动粘贴。
    private static func synthesizeCommandV() -> Bool {
        let commandFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        let vCode = CGKeyCode(kVK_ANSI_V)
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
        else {
            return false
        }
        keyDown.flags = commandFlag
        keyUp.flags = commandFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }
}
