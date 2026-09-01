import SwiftUI

/// 轻量恢复窗口：说明应用仍在跑，并提供开机自启动、检查更新、显示菜单栏图标。
struct RecoveryView: View {
    @Bindable private var preferences = AppPreferences.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case launchAtLogin
        case openLoginSettings
        case checkForUpdates
        case menuBarIcon
    }

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
            .focused($focusedControl, equals: .launchAtLogin)
            .focusEffectDisabled()
            .overlay { focusRing(for: .launchAtLogin, cornerRadius: 6) }

            if launchAtLogin.requiresApproval {
                Text(String(localized: "settings.launchAtLogin.needsApproval"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "settings.launchAtLogin.openSettings")) {
                    launchAtLogin.openSystemSettings()
                }
                .focused($focusedControl, equals: .openLoginSettings)
                .focusEffectDisabled()
                .overlay { focusRing(for: .openLoginSettings) }
            }

            if let lastErrorMessage = launchAtLogin.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(String(localized: "menu.checkForUpdates")) {
                AppDelegate.shared?.checkForUpdates()
            }
            .focused($focusedControl, equals: .checkForUpdates)
            .focusEffectDisabled()
            .overlay { focusRing(for: .checkForUpdates) }

            Toggle(
                String(localized: "settings.menuBarIcon.toggle"),
                isOn: Binding(
                    get: { preferences.isMenuBarIconVisible },
                    set: { preferences.setMenuBarIconVisible($0) }
                )
            )
            .focused($focusedControl, equals: .menuBarIcon)
            .focusEffectDisabled()
            .overlay { focusRing(for: .menuBarIcon, cornerRadius: 6) }
        }
        .padding(24)
        .frame(minWidth: 340, alignment: .leading)
        .focusEffectDisabled()
        .onAppear {
            launchAtLogin.refresh()
        }
    }

    @ViewBuilder
    private func focusRing(for control: Control, cornerRadius: CGFloat = 7) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                focusedControl == control ? Color.primary.opacity(0.65) : .clear,
                lineWidth: 1.5
            )
            .allowsHitTesting(false)
    }
}
