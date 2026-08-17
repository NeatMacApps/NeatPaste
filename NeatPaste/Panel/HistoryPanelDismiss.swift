import Foundation

nonisolated enum HistoryPanelDismiss {
    /// 点落在仍应保留的矩形上（面板、系统预览、菜单栏本图标）则不关；点到别处立刻关。
    static func shouldHide(click: CGPoint, keptFrames: [CGRect]) -> Bool {
        !keptFrames.contains { $0.contains(click) }
    }
}
