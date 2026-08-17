import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供菜单等处可靠调用；不要对 `NSApp.delegate` 做类型转换——SwiftUI 生命周期下常会失败。
    private(set) static weak var shared: AppDelegate?

    private var panel: HistoryPanel?
    private var statusItemController: StatusItemController?
    private var commaMonitor: Any?

    /// 置为 true 时允许 `applicationShouldTerminate` 放行；区分用户点击「退出」与系统自动终止。
    private var allowTermination = false

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
            onQuit: { [weak self] in self?.requestTermination() }
        )
        panel.additionalKeptFrames = { [weak statusItemController] in
            statusItemController?.buttonScreenFrame().map { [$0] } ?? []
        }

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
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTermination { return .terminateNow }
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        allowTermination = true
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
}
