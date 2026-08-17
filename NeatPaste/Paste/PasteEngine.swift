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
    static func paste(record: HistoryItem) async -> PasteOutcome {
        write(record, to: NSPasteboard.general)
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

    static func write(_ record: HistoryItem, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
        let fileDatas: [Data] = record.types.compactMap { type in
            guard type == fileURLType else { return nil }
            return record.payloads[type]
        }
        let otherTypes = record.types.filter { type in
            type != fileURLType
                && !PasteboardCapture.isFilePromise(type)
                && !PasteboardCapture.isUnsafeToRead(type)
                && record.payloads[type] != nil
        }

        if fileDatas.isEmpty {
            var didWrite = false
            for type in otherTypes {
                if let data = record.payloads[type] {
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
                    didWrite = true
                }
            }
            if !didWrite, !record.plainText.isEmpty, record.payloads.isEmpty {
                pasteboard.setString(record.plainText, forType: .string)
            }
        } else {
            // writeObjects 会整板替换，所以文本/图片必须和文件地址放在同一批条目里一次写入。
            var items: [NSPasteboardItem] = []
            let first = NSPasteboardItem()
            for type in otherTypes {
                if let data = record.payloads[type] {
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
        if pasteboard.name == NSPasteboard.Name.general {
            AppDelegate.shared?.clipboardMonitor.noteOwnWrite(changeCount: pasteboard.changeCount)
        }
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
