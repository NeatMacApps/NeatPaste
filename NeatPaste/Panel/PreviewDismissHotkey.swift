import AppKit
@preconcurrency import Carbon

/// 系统预览成为焦点后，按键不会回到历史列表。预览打开期间用临时热键收空格、Esc 和上下键。
/// 热键只响按下/抬起各一次，按住不会连发；上下键必须接到按住连走，不能只走一步。
@MainActor
final class PreviewDismissHotkey {
    var onDismiss: (@MainActor () -> Void)?
    var onMove: (@MainActor (Int) -> Void)?
    var onMoveEnd: (@MainActor (Int) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func install() {
        remove()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    let paramStatus = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard paramStatus == noErr, hotKeyID.signature == OSType(0x4E50_5156) else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let trap = Unmanaged<PreviewDismissHotkey>.fromOpaque(userData).takeUnretainedValue()
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        trap.release(id: hotKeyID.id)
                    } else {
                        trap.fire(id: hotKeyID.id)
                    }
                    return noErr
                },
                Int(buffer.count),
                buffer.baseAddress,
                selfPtr,
                &handler
            )
        }
        guard status == noErr else { return }

        register(UInt32(kVK_Space), id: 1)
        register(UInt32(kVK_Escape), id: 2)
        register(UInt32(kVK_UpArrow), id: 3)
        register(UInt32(kVK_DownArrow), id: 4)
    }

    func remove() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func register(_ keyCode: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E50_5156), id: id)
        let status = RegisterEventHotKey(keyCode, 0, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        }
    }

    nonisolated private func fire(id: UInt32) {
        Task { @MainActor in
            switch id {
            case 1, 2:
                onDismiss?()
            case 3:
                onMove?(-1)
            case 4:
                onMove?(1)
            default:
                break
            }
        }
    }

    nonisolated private func release(id: UInt32) {
        Task { @MainActor in
            switch id {
            case 3:
                onMoveEnd?(-1)
            case 4:
                onMoveEnd?(1)
            default:
                break
            }
        }
    }
}
