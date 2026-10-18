import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppPreferences.Key.selectedSettingsPane)
    private var selectedPane = AppPreferences.selectedSettingsPaneDefault

    var body: some View {
        TabView(selection: $selectedPane) {
            Tab(String(localized: "settings.tabs.general"), systemImage: "gearshape", value: "general") {
                GeneralSettingsPane()
            }
            Tab(String(localized: "settings.tabs.ignored"), systemImage: "eye.slash", value: "ignored") {
                IgnoredApplicationsPane()
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .focusEffectDisabled()
        .background(SettingsWindowAttachment().frame(width: 0, height: 0))
        .onChange(of: selectedPane) { _, _ in HotkeyManager.shared.stopRecording() }
        .onExitCommand { SettingsWindowController.shared.close() }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var preferences = AppPreferences.shared

    var body: some View {
        Form {
            if !preferences.isMenuBarIconVisible {
                Section {
                    Label(String(localized: "recovery.running.title"), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(String(localized: "recovery.running.detail"))
                }
            }
            Section {
                shortcutRow
                if let message = hotkeyManager.lastErrorMessage {
                    Text(message).foregroundStyle(.red)
                }
                LabeledContent(String(localized: "settings.history")) {
                    Button(String(localized: "menu.openPanel")) {
                        AppDelegate.shared?.showPanel()
                    }
                }
            }
            Section {
                Toggle(
                    String(localized: "settings.launchAtLogin.section"),
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button(String(localized: "settings.launchAtLogin.openSettings")) {
                            launchAtLogin.openSystemSettings()
                        }
                    } label: {
                        Label(String(localized: "settings.launchAtLogin.needsApproval"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if let message = launchAtLogin.lastErrorMessage {
                    Text(message).foregroundStyle(.red)
                }
                Toggle(
                    String(localized: "settings.menuBarIcon.toggle"),
                    isOn: Binding(
                        get: { preferences.isMenuBarIconVisible },
                        set: { preferences.setMenuBarIconVisible($0) }
                    )
                )
            }
            Section { SettingsAboutRow() }
        }
        .settingsPaneStyle()
        .onAppear { launchAtLogin.refresh() }
        .onDisappear { hotkeyManager.stopRecording() }
    }

    private var shortcutRow: some View {
        LabeledContent(String(localized: "settings.hotkey.section")) {
            HStack(spacing: 8) {
                Button {
                    hotkeyManager.beginRecording()
                } label: {
                    Text(hotkeyManager.isRecording
                        ? String(localized: "settings.hotkey.recording")
                        : hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.record"))
                        .monospacedDigit()
                }
                .disabled(hotkeyManager.isRecording)
                .help(String(localized: hotkeyManager.isRecording
                    ? "settings.hotkey.recordingHint" : "settings.hotkey.hint"))
                .accessibilityLabel(String(localized: "settings.hotkey.record"))
                .accessibilityValue(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                Menu {
                    Button(String(localized: "settings.hotkey.clear")) { hotkeyManager.clearShortcut() }
                    Button(String(localized: "settings.hotkey.restore")) { hotkeyManager.restoreSafeDefault() }
                } label: {
                    Label(String(localized: "settings.hotkey.actions"), systemImage: "ellipsis")
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

private struct SettingsAboutRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "NeatPaste",
                    .credits: NSAttributedString(string: String(localized: "about.credits"))
                ])
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "NeatPaste").fontWeight(.medium)
                        Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(String(localized: "menu.about"))
            .accessibilityLabel(String(localized: "menu.about"))
            Spacer(minLength: 12)
            Button(String(localized: "menu.checkForUpdates")) { AppDelegate.shared?.checkForUpdates() }
            Button(String(localized: "menu.quit")) { AppDelegate.shared?.requestTermination() }
        }
    }
}

private struct IgnoredApplicationsPane: View {
    @Bindable private var preferences = AppPreferences.shared
    @State private var selection: String?
    @State private var invalidApplication = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(preferences.ignoredAppBundleIDs, id: \.self, selection: $selection) { bundleID in
                IgnoredApplicationRow(bundleID: bundleID)
                    .help(bundleID)
            }
            .overlay {
                if preferences.ignoredAppBundleIDs.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "settings.ignoredApps.empty"), systemImage: "eye.slash")
                    } description: {
                        Text(String(localized: "settings.ignoredApps.help"))
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: min(max(CGFloat(preferences.ignoredAppBundleIDs.count) * 36 + 32, 190), 350))
            HStack {
                Button(String(localized: "settings.ignoredApps.add"), action: addApplications)
                Button(String(localized: "settings.ignoredApps.remove"), role: .destructive) {
                    if let selection {
                        preferences.removeIgnoredApplication(bundleID: selection)
                        self.selection = nil
                    }
                }
                .disabled(selection == nil)
                Spacer()
            }
            if !preferences.ignoredAppBundleIDs.isEmpty {
                Text(String(localized: "settings.ignoredApps.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .focusEffectDisabled()
        .alert(String(localized: "settings.ignoredApps.invalid"), isPresented: $invalidApplication) {
            Button(String(localized: "settings.ok"), role: .cancel) {}
        }
    }

    private func addApplications() {
        guard let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "settings.ignoredApps.choose")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            for url in panel.urls {
                guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
                    invalidApplication = true
                    continue
                }
                preferences.addIgnoredApplication(bundleID: bundleID)
                selection = bundleID
            }
        }
    }
}

private struct IgnoredApplicationRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(verbatim: url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}

private extension View {
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .toggleStyle(.switch)
            .modifier(SettingsContentHeight())
            .focusEffectDisabled()
    }
}

private struct SettingsContentHeight: ViewModifier {
    @State private var contentHeight: CGFloat?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
                contentHeight = height
            }
            .scrollDisabled(true)
            .frame(height: contentHeight)
    }
}
