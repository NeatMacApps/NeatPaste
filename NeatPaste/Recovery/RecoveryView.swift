import SwiftUI

/// 轻量恢复窗口：说明应用仍在跑，并提供开机自启动、检查更新、显示菜单栏图标。
struct RecoveryView: View {
    @Bindable private var preferences = AppPreferences.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "recovery.running.title"))
                    .font(.title3.weight(.semibold))
                Text(String(localized: "recovery.running.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(
                String(localized: "settings.launchAtLogin.toggle"),
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .focusEffectDisabled()

            if launchAtLogin.requiresApproval {
                Text(String(localized: "settings.launchAtLogin.needsApproval"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "settings.launchAtLogin.openSettings")) {
                    launchAtLogin.openSystemSettings()
                }
                .focusEffectDisabled()
            }

            if let lastErrorMessage = launchAtLogin.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(String(localized: "menu.checkForUpdates")) {
                AppDelegate.shared?.checkForUpdates()
            }
            .focusEffectDisabled()

            Toggle(
                String(localized: "settings.menuBarIcon.toggle"),
                isOn: Binding(
                    get: { preferences.isMenuBarIconVisible },
                    set: { preferences.setMenuBarIconVisible($0) }
                )
            )
            .focusEffectDisabled()
        }
        .padding(24)
        .frame(minWidth: 340, alignment: .leading)
        .focusEffectDisabled()
        .onAppear {
            launchAtLogin.refresh()
        }
    }
}
