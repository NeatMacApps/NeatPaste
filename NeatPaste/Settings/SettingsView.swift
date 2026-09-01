import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var preferences = AppPreferences.shared
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case record
        case clear
        case restore
        case launchAtLogin
        case openLoginSettings
        case menuBarIcon
    }

    var body: some View {
        Form {
            hotkeySection
            launchAtLoginSection
            menuBarIconSection
            ignoredAppsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 380)
        .padding(.bottom, 8)
        .focusEffectDisabled()
        .onAppear {
            launchAtLogin.refresh()
        }
        .onDisappear {
            hotkeyManager.stopRecording()
        }
    }

    private var hotkeySection: some View {
        Section(String(localized: "settings.hotkey.section")) {
            Text(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .accessibilityLabel(String(localized: "settings.hotkey.current"))
                .accessibilityValue(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))

            Text(hotkeyManager.isRecording
                 ? String(localized: "settings.hotkey.recordingHint")
                 : String(localized: "settings.hotkey.hint"))
                .foregroundStyle(.secondary)

            HStack {
                Button(hotkeyManager.isRecording
                       ? String(localized: "settings.hotkey.recording")
                       : String(localized: "settings.hotkey.record")) {
                    hotkeyManager.beginRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hotkeyManager.isRecording)
                .focused($focusedControl, equals: .record)
                .focusEffectDisabled()
                .overlay { focusRing(for: .record) }

                Button(String(localized: "settings.hotkey.clear")) {
                    hotkeyManager.clearShortcut()
                }
                .buttonStyle(.bordered)
                .focused($focusedControl, equals: .clear)
                .focusEffectDisabled()
                .overlay { focusRing(for: .clear) }

                Button(String(localized: "settings.hotkey.restore")) {
                    hotkeyManager.restoreSafeDefault()
                }
                .buttonStyle(.bordered)
                .focused($focusedControl, equals: .restore)
                .focusEffectDisabled()
                .overlay { focusRing(for: .restore) }
            }

            if let message = hotkeyManager.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var launchAtLoginSection: some View {
        Section(String(localized: "settings.launchAtLogin.section")) {
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
        }
    }

    private var menuBarIconSection: some View {
        Section(String(localized: "settings.menuBarIcon.section")) {
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
    }

    private var ignoredAppsSection: some View {
        Section(String(localized: "settings.ignoredApps.section")) {
            if AppPreferences.shared.ignoredAppBundleIDs.isEmpty {
                Text(String(localized: "settings.ignoredApps.empty"))
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "settings.ignoredApps.footnote"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
