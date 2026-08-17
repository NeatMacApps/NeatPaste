import AppKit
import CoreGraphics
import Foundation

/// 非激活浮层经常收不到系统按键连发；把按下吞掉后，系统也可能不再连发。
/// 按系统连发延迟/间隔自己走步；抬起、键已松开或关掉面板时停。系统连发若仍到达则丢掉，避免跳两格。
@MainActor
final class ArrowKeyRepeat {
    private let delay: TimeInterval
    private let interval: TimeInterval
    private let isKeyPressed: (UInt16) -> Bool
    private var timer: Timer?
    private var heldKeyCode: UInt16?
    private var heldDelta: Int?

    var onStep: ((Int) -> Void)?

    init(
        delay: TimeInterval = NSEvent.keyRepeatDelay,
        interval: TimeInterval = NSEvent.keyRepeatInterval,
        isKeyPressed: @escaping (UInt16) -> Bool = { CGEventSource.keyState(.hidSystemState, key: $0) }
    ) {
        self.delay = delay
        self.interval = interval
        self.isKeyPressed = isKeyPressed
    }

    func keyDown(keyCode: UInt16, isARepeat: Bool, delta: Int) {
        if isARepeat { return }
        // 预览开着时热键、预览窗、列表可能同时收到第一次按下；已按住则不再走步。
        if heldKeyCode == keyCode { return }
        stop()
        heldKeyCode = keyCode
        heldDelta = delta
        onStep?(delta)
        scheduleFirstRepeat()
    }

    func keyUp(keyCode: UInt16) {
        guard keyCode == heldKeyCode else { return }
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        heldKeyCode = nil
        heldDelta = nil
    }

    private func scheduleFirstRepeat() {
        let wait = max(delay, 0.015)
        let next = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.beginRepeating()
            }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func beginRepeating() {
        guard continueHeldStep() else { return }
        timer?.invalidate()
        let pace = max(interval, 0.015)
        let next = Timer(timeInterval: pace, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = self?.continueHeldStep()
            }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    @discardableResult
    private func continueHeldStep() -> Bool {
        guard let keyCode = heldKeyCode, let delta = heldDelta, isKeyPressed(keyCode) else {
            stop()
            return false
        }
        onStep?(delta)
        return true
    }
}
