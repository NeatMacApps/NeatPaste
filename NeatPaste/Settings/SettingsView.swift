import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var preferences = AppPreferences.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(String(localized: "settings.tabs.general"), systemImage: "gearshape")
                }
            ignoredAppsTab
                .tabItem {
                    Label(String(localized: "settings.tabs.ignored"), systemImage: "eye.slash")
                }
            moreTab
                .tabItem {
                    Label(String(localized: "settings.tabs.more"), systemImage: "ellipsis.circle")
                }
        }
        .padding(20)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
        .onAppear {
            launchAtLogin.refresh()
        }
        .onDisappear {
            hotkeyManager.stopRecording()
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !preferences.isMenuBarIconVisible {
                runningStatusCard
            }
            shortcutCard
            launchCard
            menuBarIconCard
        }
    }

    private var ignoredAppsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                Text(String(localized: "settings.ignoredApps.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var moreTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 右键菜单对等入口：藏图标后仍能从设置窗完成这些操作。
            actionsCard
            Text(versionFooter)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var runningStatusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "recovery.running.title"))
                    .font(.headline)
                Text(String(localized: "recovery.running.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shortcutCard: some View {
        GroupBox(label: Label(String(localized: "settings.hotkey.section"), systemImage: "keyboard")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .accessibilityLabel(String(localized: "settings.hotkey.current"))
                    .accessibilityValue(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                Text(hotkeyManager.isRecording
                    ? String(localized: "settings.hotkey.recordingHint")
                    : String(localized: "settings.hotkey.hint"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(hotkeyManager.isRecording
                        ? String(localized: "settings.hotkey.recording")
                        : String(localized: "settings.hotkey.record")) {
                            hotkeyManager.beginRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(hotkeyManager.isRecording)
                        .focusEffectDisabled()
                    Button(String(localized: "settings.hotkey.clear")) {
                        hotkeyManager.clearShortcut()
                    }
                    .buttonStyle(.bordered)
                    .focusEffectDisabled()
                    Button(String(localized: "settings.hotkey.restore")) {
                        hotkeyManager.restoreSafeDefault()
                    }
                    .buttonStyle(.bordered)
                    .focusEffectDisabled()
                }
                if let message = hotkeyManager.lastErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var launchCard: some View {
        GroupBox(label: Label(String(localized: "settings.launchAtLogin.section"), systemImage: "bolt.circle")) {
            VStack(alignment: .leading, spacing: 8) {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var menuBarIconCard: some View {
        GroupBox(label: Label(String(localized: "settings.menuBarIcon.section"), systemImage: "eye")) {
            Toggle(
                String(localized: "settings.menuBarIcon.toggle"),
                isOn: Binding(
                    get: { preferences.isMenuBarIconVisible },
                    set: { preferences.setMenuBarIconVisible($0) }
                )
            )
            .focusEffectDisabled()
        }
    }

    private var actionsCard: some View {
        GroupBox(label: Label(String(localized: "settings.actions.section"), systemImage: "ellipsis.circle")) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    AppDelegate.shared?.showPanel()
                } label: {
                    Label(String(localized: "menu.openPanel"), systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .focusEffectDisabled()
                Divider()
                    .padding(.vertical, 4)
                actionRow(
                    title: String(localized: "menu.checkForUpdates"),
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    AppDelegate.shared?.checkForUpdates()
                }
                Divider()
                actionRow(
                    title: String(localized: "menu.about"),
                    systemImage: "info.circle"
                ) {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "NeatPaste",
                        .credits: NSAttributedString(string: String(localized: "about.credits"))
                    ])
                }
                Divider()
                actionRow(
                    title: String(localized: "menu.quit"),
                    systemImage: "power"
                ) {
                    AppDelegate.shared?.requestTermination()
                }
            }
        }
    }

    private func actionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
    }

    /// Bundle version, read live so the xcconfig single source stays authoritative.
    private var versionFooter: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(String(localized: "settings.version.label")) \(short) (\(build))"
    }
}
