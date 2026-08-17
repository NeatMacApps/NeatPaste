import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let launchAtLoginItem: NSMenuItem
    private let onOpenPanel: () -> Void
    private let onTogglePanel: () -> Void
    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onOpenPanel: @escaping () -> Void,
        onTogglePanel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenPanel = onOpenPanel
        self.onTogglePanel = onTogglePanel
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        launchAtLoginItem = NSMenuItem(
            title: String(localized: "menu.launchAtLogin"),
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        super.init()

        launchAtLoginItem.target = self
        configureMenu()
        configureButton()
        refreshLaunchAtLoginState()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "clipboard", accessibilityDescription: String(localized: "status.item.accessibility"))
        image?.isTemplate = true
        button.image = image
        button.image?.isTemplate = true
        button.setAccessibilityLabel(String(localized: "status.item.accessibility"))
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.focusRingType = .none
    }

    private func configureMenu() {
        let openItem = NSMenuItem(
            title: String(localized: "menu.openPanel"),
            action: #selector(openPanel(_:)),
            keyEquivalent: ""
        )
        openItem.target = self

        let settingsItem = NSMenuItem(
            title: String(localized: "menu.settings"),
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self

        let aboutItem = NSMenuItem(
            title: String(localized: "menu.about"),
            action: #selector(openAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self

        let checkForUpdatesItem = NSMenuItem(
            title: String(localized: "menu.checkForUpdates"),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self

        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.items = [
            openItem,
            settingsItem,
            .separator(),
            launchAtLoginItem,
            .separator(),
            checkForUpdatesItem,
            aboutItem,
            quitItem
        ]
    }

    func buttonScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc
    private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            onTogglePanel()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            refreshLaunchAtLoginState()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onTogglePanel()
        }
    }

    @objc
    private func openPanel(_ sender: Any?) {
        onOpenPanel()
    }

    @objc
    private func openSettings(_ sender: Any?) {
        onOpenSettings()
    }

    @objc
    private func toggleLaunchAtLogin(_ sender: Any?) {
        let manager = LaunchAtLoginManager.shared
        manager.setEnabled(!manager.isEnabled)
        refreshLaunchAtLoginState()
    }

    @objc
    private func openAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "NeatPaste",
            .credits: NSAttributedString(string: String(localized: "about.credits"))
        ])
    }

    @objc
    private func checkForUpdates(_ sender: Any?) {
        onCheckForUpdates()
    }

    @objc
    private func quit(_ sender: Any?) {
        onQuit()
    }

    private func refreshLaunchAtLoginState() {
        LaunchAtLoginManager.shared.refresh()
        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        if LaunchAtLoginManager.shared.requiresApproval {
            launchAtLoginItem.state = .mixed
        }
    }
}
