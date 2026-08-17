import AppKit
import Foundation

/// 固定 0.5 秒查看系统剪贴板是否变化；变化后组装快照写入历史。
@MainActor
final class ClipboardMonitor {
    private let history: any HistoryServing
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var ownWriteChangeCount: Int?

    init(history: any HistoryServing) {
        self.history = history
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        stop()
        let interval = AppPreferences.clipboardPollInterval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task {
            await history.sweepExpired(olderThan: Date().addingTimeInterval(-AppPreferences.historyLifetime))
        }
        NSLog("[NeatPaste] 剪贴板监听已启动，探测间隔 %f 秒", interval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 本应用把历史条目写回系统剪贴板之后调用，避免这条写回再被当成新复制。
    func noteOwnWrite(changeCount: Int) {
        ownWriteChangeCount = changeCount
        lastChangeCount = changeCount
    }

    func poll() async {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        let advertised = pasteboard.types?.map(\.rawValue) ?? []
        NSLog("[NeatPaste] 剪贴板变化 changeCount=%d 类型数=%d %@", changeCount, advertised.count, advertised.joined(separator: ","))

        if ownWriteChangeCount == changeCount {
            lastChangeCount = changeCount
            NSLog("[NeatPaste] 跳过本应用写回")
            return
        }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ignoredApps = AppPreferences.shared.ignoredAppBundleIDs
        let decision = PasteboardCapture.decide(
            types: advertised,
            sourceBundleID: sourceBundleID,
            ignoredApps: ignoredApps
        )
        let snapshot = PasteboardCapture.snapshot(
            from: pasteboard,
            sourceBundleID: sourceBundleID,
            ignoredApps: ignoredApps
        )
        let didCapture = snapshot != nil
        if !PasteboardCapture.shouldAdvanceChangeCount(decision: decision, didCapture: didCapture) {
            NSLog("[NeatPaste] 快照为空，保留变化计数以便重试")
            return
        }
        lastChangeCount = changeCount

        if decision != .capture {
            NSLog("[NeatPaste] 跳过收录：%@ 来源=%@", String(describing: decision), sourceBundleID ?? "nil")
            return
        }
        guard let snapshot else { return }
        await history.ingest(snapshot)
    }
}
