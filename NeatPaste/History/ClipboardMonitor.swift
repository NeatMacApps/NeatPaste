import AppKit
import Foundation

/// 第一波只保留骨架。下一波在 `start()` 里用 0.5 秒间隔轮询 `NSPasteboard.general.changeCount`，
/// 发现变化后组装 `PasteboardSnapshot` 并调用 `history.ingest`。
@MainActor
final class ClipboardMonitor {
    private let history: any HistoryServing
    private var timer: Timer?
    private var lastChangeCount: Int = 0

    init(history: any HistoryServing) {
        self.history = history
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        // 第一波不启动轮询，避免在假数据阶段把真实剪贴板写进内存实现。
        print("[NeatPaste] 剪贴板监听骨架已就绪，探测间隔 \(AppPreferences.clipboardPollInterval) 秒，本波不轮询")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
