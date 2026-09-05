import AppKit
import Foundation

/// 固定 0.5 秒查看系统剪贴板是否变化；变化后组装快照写入历史。
@MainActor
final class ClipboardMonitor {
    private let history: any HistoryServing
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var ownWriteChangeCount: Int?
    /// 防止定时器与打开面板同时 poll 时，在 await ingest 间隙重入导致同一变化双收录。
    private var isPolling = false

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
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        let advertised = pasteboard.types?.map(\.rawValue) ?? []
        NSLog("[NeatPaste] 剪贴板变化 changeCount=%d 类型数=%d %@", changeCount, advertised.count, advertised.joined(separator: ","))

        if ownWriteChangeCount == changeCount {
            guard Self.isChangeCountStable(observed: changeCount, current: pasteboard.changeCount) else {
                NSLog("[NeatPaste] 本应用写回计数已漂移，下次再试")
                return
            }
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

        // 敏感/自写/忽略：只按类型判定，不读载荷；计数仍须稳定才推进。
        if decision != .capture {
            guard Self.isChangeCountStable(observed: changeCount, current: pasteboard.changeCount) else {
                NSLog("[NeatPaste] 跳过判定后剪贴板又变了，下次再试")
                return
            }
            lastChangeCount = changeCount
            NSLog("[NeatPaste] 跳过收录：%@ 来源=%@", String(describing: decision), sourceBundleID ?? "nil")
            return
        }

        let snapshot = PasteboardCapture.snapshot(
            from: pasteboard,
            sourceBundleID: sourceBundleID,
            ignoredApps: ignoredApps
        )
        let didCapture = snapshot != nil
        if !PasteboardCapture.shouldAdvanceChangeCount(decision: .capture, didCapture: didCapture) {
            NSLog("[NeatPaste] 快照为空，保留变化计数以便重试")
            return
        }
        // 读载荷期间其它进程可能已改板；计数漂移则放弃本次，避免用旧计数吞掉新变化或双收。
        guard Self.isChangeCountStable(observed: changeCount, current: pasteboard.changeCount) else {
            NSLog("[NeatPaste] 收录过程中剪贴板又变了，下次再试")
            return
        }
        lastChangeCount = changeCount

        guard let snapshot else { return }
        await history.ingest(snapshot)
    }

    /// 观测到的变化计数与当前板是否仍一致。
    nonisolated static func isChangeCountStable(observed: Int, current: Int) -> Bool {
        observed == current
    }
}
