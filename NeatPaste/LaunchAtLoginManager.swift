import Combine
import MacKitCore
import MacKitLaunchAtLogin

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var status: LaunchAtLoginStatus = .off
    @Published private(set) var lastErrorMessage: String?

    private let service = LaunchAtLoginService()

    /// 只有系统真正会在登录时拉起才算开。待批准不能算已启用。
    var isEnabled: Bool { status.isEffectivelyEnabled }

    var requiresApproval: Bool { status == .needsApproval }

    private init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        if requiresApproval, enabled {
            openSystemSettings()
            refresh()
            return
        }
        switch service.setEnabled(enabled) {
        case .success(let status):
            self.status = status
            lastErrorMessage = nil
        case .failure:
            refresh()
            lastErrorMessage = String(localized: "settings.launchAtLogin.failed")
        }
    }

    func refresh() {
        service.refresh()
        status = service.status
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
