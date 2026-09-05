import AppKit
import MacKitCore
import MacKitLifecycle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供菜单等处可靠调用；不要对 `NSApp.delegate` 做类型转换——SwiftUI 生命周期下常会失败。
    private(set) static weak var shared: AppDelegate?

    private var panel: HistoryPanel?
    private var statusItemController: StatusItemController?
    private var commaMonitor: Any?
    private let appUpdater = AppUpdater()
    private let terminationGuard = TerminationGuard()

    let history: InMemoryHistoryStore
    let clipboardMonitor: ClipboardMonitor
    let panelModel: HistoryPanelModel

    override init() {
        let history = InMemoryHistoryStore(storageURL: InMemoryHistoryStore.defaultStorageURL())
        self.history = history
        self.clipboardMonitor = ClipboardMonitor(history: history)
        self.panelModel = HistoryPanelModel(history: history)
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        clipboardMonitor.start()
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.appUpdater.updater.sessionInProgress ?? false
        }

        let panel = HistoryPanel(model: panelModel)
        panel.orderOut(nil)
        self.panel = panel
        panelModel.onHide = { [weak panel] in
            panel?.hidePanel()
        }
        panelModel.onSuppressClickThrough = { [weak panel] in
            panel?.suppressClickThrough()
        }
        panelModel.onPasteOutcome = { [weak self] outcome in
            if outcome == .copiedOnly {
                self?.panelModel.needsAccessibilityPrompt = true
            }
        }

        statusItemController = StatusItemController(
            onOpenPanel: { [weak self] in self?.showPanel() },
            onTogglePanel: { [weak self] in self?.togglePanel() },
            onOpenSettings: { SettingsWindowController.shared.show() },
            onCheckForUpdates: { [weak appUpdater] in appUpdater?.checkForUpdates(nil) },
            onQuit: { [weak self] in self?.requestTermination() }
        )
        panel.additionalKeptFrames = { [weak statusItemController] in
            statusItemController?.buttonScreenFrame().map { [$0] } ?? []
        }
        applyMenuBarIconVisibility()

        HotkeyManager.shared.onHotKey = { [weak self] in
            self?.togglePanel()
        }
        HotkeyManager.shared.register()

        commaMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if command, event.charactersIgnoringModifiers == "," {
                SettingsWindowController.shared.show()
                return nil
            }
            return event
        }

        let isLoginLaunch = LoginLaunchDetector.isLaunchedAsLoginItem
        if MenuBarReopenPolicy.shouldShowRecoveryWindow(
            iconVisible: AppPreferences.shared.isMenuBarIconVisible,
            isLoginLaunch: isLoginLaunch
        ) {
            showRecoveryWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 图标隐藏时出示恢复窗；不要开关历史面板——点外面关的浮层不能当恢复面。
        if MenuBarReopenPolicy.presentation(
            iconVisible: AppPreferences.shared.isMenuBarIconVisible,
            isReopenOrLaunch: true
        ) == .showRecoveryWindow {
            showRecoveryWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        clipboardMonitor.stop()
        if let commaMonitor {
            NSEvent.removeMonitor(commaMonitor)
        }
    }

    /// 用户主动退出：先放行再 terminate。
    func requestTermination(terminate: () -> Void = { NSApplication.shared.terminate(nil) }) {
        terminationGuard.allowTermination = true
        terminate()
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel else { return }
        // 必须在异步刷新之前记下光标，否则面板一旦成为焦点就只能锚到自己身上。
        let frame = PanelAnchor.frame(for: AppPreferences.panelSize)
        Task { @MainActor in
            await clipboardMonitor.poll()
            await panelModel.reload()
            panel.showPanel(frame: frame)
        }
    }

    func applyMenuBarIconVisibility() {
        statusItemController?.isVisible = AppPreferences.shared.isMenuBarIconVisible
    }

    /// 出示恢复窗口前先关掉历史面板，避免激活本应用后粘贴贴到自己身上。
    func showRecoveryWindow() {
        panel?.hidePanel()
        RecoveryWindowController.shared.show()
    }

    func checkForUpdates() {
        appUpdater.checkForUpdates(nil)
    }
}
