import MacKitLifecycle

/// 设置窗和恢复窗共用一次激活切换：打开第一扇普通窗口时从附件切到可激活，关掉最后一扇再改回。
@MainActor
enum TitledWindowActivation {
    private static let session = AccessoryActivationSession()
    private static var openCount = 0

    static func windowDidShow() {
        if openCount == 0 {
            session.beginIfAccessory()
        }
        openCount += 1
    }

    static func windowWillClose() {
        openCount = max(0, openCount - 1)
        if openCount == 0 {
            session.endIfNeeded()
        }
    }
}
