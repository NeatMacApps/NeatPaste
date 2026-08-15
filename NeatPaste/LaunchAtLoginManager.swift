import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var lastErrorMessage: String?

    private init() {}

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }

            lastErrorMessage = nil
            refresh()
        } catch {
            refresh()
            lastErrorMessage = String(localized: "settings.launchAtLogin.failed")
            print("[NeatPaste] 开机自启动更新失败：\(error)")
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
