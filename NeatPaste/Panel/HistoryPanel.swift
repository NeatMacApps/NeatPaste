import AppKit
import QuickLookUI
@preconcurrency import Carbon
import SwiftUI

@MainActor
final class HistoryPanel: NSPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let model: HistoryPanelModel
    private var hostingView: NSHostingView<HistoryPanelView>?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var outsideClickLocalMonitor: Any?
    /// 菜单栏本图标等点击后仍应由原入口处理开关，不能当成「点外面」。
    var additionalKeptFrames: () -> [NSRect] = { [] }
    private var previewItem: ClipboardQuickLookItem?
    private var isPresentingQuickLook = false
    private var isApplyingQuickLookFrame = false
    private var quickLookResizeObserver: NSObjectProtocol?
    private let dismissHotkey = PreviewDismissHotkey()
    private let arrowRepeat = ArrowKeyRepeat()
    private var clickThroughEater: ClickThroughEater?

    init(model: HistoryPanelModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: AppPreferences.panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = AppPreferences.panelSize
        maxSize = AppPreferences.panelSize

        let hosting = NSHostingView(rootView: HistoryPanelView(model: model))
        hosting.frame = contentRect(forFrameRect: frame)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView = hosting
        contentView = makeChromeView(hosting)

        model.onSelectionChange = { [weak self] in
            self?.reloadQuickLookIfVisible()
        }
        dismissHotkey.onDismiss = { [weak self] in
            self?.closeQuickLook()
        }
        dismissHotkey.onMove = { [weak self] delta in
            self?.beginHeldArrow(delta)
        }
        dismissHotkey.onMoveEnd = { [weak self] delta in
            self?.endHeldArrow(delta)
        }
        arrowRepeat.onStep = { [weak self] delta in
            self?.model.moveSelection(delta)
        }
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc(_hasActiveAppearance)
    func hasActiveAppearanceForGlass() -> Bool { true }

    @objc(hasActiveAppearance)
    func hasPublicActiveAppearanceForGlass() -> Bool { true }

    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    func hasActiveAppearanceIgnoringKeyFocusForGlass() -> Bool { true }

    @objc(_hasActiveControls)
    func hasActiveControlsForGlass() -> Bool { true }

    @objc(_hasKeyAppearance)
    func hasKeyAppearanceForGlass() -> Bool { true }

    @objc(hasKeyAppearance)
    func hasPublicKeyAppearanceForGlass() -> Bool { true }

    @objc(_hasMainAppearance)
    func hasMainAppearanceForGlass() -> Bool { true }

    @objc(hasMainAppearance)
    func hasPublicMainAppearanceForGlass() -> Bool { true }

    func showPanel(frame: NSRect? = nil) {
        clickThroughEater?.cancel()
        clickThroughEater = nil
        setFrame(frame ?? PanelAnchor.frame(for: AppPreferences.panelSize), display: true)
        orderFrontRegardless()
        makeKey()
        installKeyMonitor()
        installOutsideClickMonitor()
    }

    /// 鼠标粘贴后挡住双击收尾那一下，避免点穿到正在输入的窗口。
    func suppressClickThrough() {
        clickThroughEater?.cancel()
        let eater = ClickThroughEater()
        eater.cover(frame, duration: NSEvent.doubleClickInterval)
        clickThroughEater = eater
    }

    func hidePanel() {
        arrowRepeat.stop()
        closeQuickLook()
        removeKeyMonitor()
        removeOutsideClickMonitor()
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        if isPresentingQuickLook || isQuickLookVisible { return }
        hidePanel()
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        performOnMain {
            panel.delegate = self
            panel.dataSource = self
            watchQuickLookResize(panel)
            constrainQuickLook(panel)
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        performOnMain {
            previewItem = nil
            isPresentingQuickLook = false
            dismissHotkey.remove()
            stopWatchingQuickLookResize()
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        performOnMain { previewItem == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        performOnMain { previewItem }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        let eventType = event.type
        let keyCode = Int(event.keyCode)
        let keyCodeRaw = event.keyCode
        let isRepeat = event.isARepeat
        return performOnMain {
            if eventType == .keyUp {
                switch keyCode {
                case 125, 126:
                    arrowRepeat.keyUp(keyCode: keyCodeRaw)
                    return true
                default:
                    return false
                }
            }
            guard eventType == .keyDown else { return false }
            switch keyCode {
            case 49, 53:
                closeQuickLook()
                return true
            case 126:
                arrowRepeat.keyDown(keyCode: keyCodeRaw, isARepeat: isRepeat, delta: -1)
                return true
            case 125:
                arrowRepeat.keyDown(keyCode: keyCodeRaw, isARepeat: isRepeat, delta: 1)
                return true
            default:
                return false
            }
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === QLPreviewPanel.shared() else { return frameSize }
        return AppPreferences.quickLookSize
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel else { return }
        applyQuickLookFrame(panel)
    }

    private nonisolated func performOnMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    private var isQuickLookVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible == true)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            let belongsToPanel = event.window === self
                || event.window === QLPreviewPanel.shared()
                || (event.window == nil && NSApp.keyWindow === self)
            guard belongsToPanel else { return event }
            if event.type == .keyUp {
                return self.handleKeyUp(event)
            }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        arrowRepeat.stop()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // 点到别的应用时本窗口往往不会失焦：浮层并不把本应用切到前台，底下那个应用本来就是前台。
        // 必须靠全局按下监听立刻收起，否则会挡屏幕。不要用「本应用失活」来关，否则一打开就会被关掉。
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in
            let point = NSEvent.mouseLocation
            self?.performOnMain {
                self?.handleOutsideMouseDown(at: point, eventWindow: nil)
            }
        }
        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
            guard let self else { return event }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self.handleOutsideMouseDown(at: point, eventWindow: event.window)
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }
    }

    private func handleOutsideMouseDown(at point: NSPoint, eventWindow: NSWindow?) {
        guard isVisible else { return }
        if eventWindow === self { return }
        if let preview = QLPreviewPanel.shared(), eventWindow === preview { return }
        // 列表右键菜单落在弹出层上：点菜单项不能当成「点外面」关面板。
        if Self.isContextMenuWindow(eventWindow) { return }

        var kept = [frame] + additionalKeptFrames()
        if let preview = QLPreviewPanel.shared(), preview.isVisible {
            kept.append(preview.frame)
        }
        guard HistoryPanelDismiss.shouldHide(click: point, keptFrames: kept) else { return }
        hidePanel()
    }

    private static func isContextMenuWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.level == .popUpMenu { return true }
        let name = String(describing: type(of: window))
        return name.contains("Menu")
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if let client = firstResponder as? NSTextInputClient, client.hasMarkedText() {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers == "," {
            SettingsWindowController.shared.show()
            return nil
        }

        switch Int(event.keyCode) {
        case 126:
            arrowRepeat.keyDown(keyCode: event.keyCode, isARepeat: event.isARepeat, delta: -1)
            return nil
        case 125:
            arrowRepeat.keyDown(keyCode: event.keyCode, isARepeat: event.isARepeat, delta: 1)
            return nil
        case 49:
            let blocking = flags.intersection([.command, .option, .control])
            if blocking.isEmpty {
                toggleQuickLook()
                return nil
            }
            return event
        case 36, 76:
            Task { await model.confirmPaste() }
            return nil
        case 53:
            if isPresentingQuickLook || isQuickLookVisible {
                closeQuickLook()
                return nil
            }
            hidePanel()
            return nil
        default:
            return event
        }
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case 125, 126:
            arrowRepeat.keyUp(keyCode: event.keyCode)
            if let client = firstResponder as? NSTextInputClient, client.hasMarkedText() {
                return event
            }
            return nil
        default:
            return event
        }
    }

    private func beginHeldArrow(_ delta: Int) {
        let keyCode: UInt16 = delta < 0 ? 126 : 125
        arrowRepeat.keyDown(keyCode: keyCode, isARepeat: false, delta: delta)
    }

    private func endHeldArrow(_ delta: Int) {
        let keyCode: UInt16 = delta < 0 ? 126 : 125
        arrowRepeat.keyUp(keyCode: keyCode)
    }

    private func toggleQuickLook() {
        if isPresentingQuickLook || isQuickLookVisible {
            closeQuickLook()
            return
        }
        guard let item = model.selectedItem else { return }
        do {
            let url = try QuickLookPreviewFile.makeURL(for: item)
            previewItem = ClipboardQuickLookItem(url: url, title: String(localized: "panel.preview.title"))
            guard let panel = QLPreviewPanel.shared() else { return }
            isPresentingQuickLook = true
            panel.animationBehavior = .none
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            lockQuickLookSize(panel)
            constrainQuickLook(panel)
            watchQuickLookResize(panel)
            dismissHotkey.install()
        } catch {
            isPresentingQuickLook = false
            print("[NeatPaste] 无法打开系统预览：\(error.localizedDescription)")
        }
    }

    private func closeQuickLook() {
        isPresentingQuickLook = false
        dismissHotkey.remove()
        stopWatchingQuickLookResize()
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared()?.orderOut(nil)
        }
        if isVisible {
            orderFrontRegardless()
            makeKey()
        }
    }

    private func constrainQuickLook(_ panel: QLPreviewPanel) {
        applyQuickLookFrame(panel)
        for delay in [0.05, 0.2] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
                self.applyQuickLookFrame(panel)
            }
        }
    }

    private func lockQuickLookSize(_ panel: QLPreviewPanel) {
        let size = AppPreferences.quickLookSize
        panel.animationBehavior = .none
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
    }

    private func applyQuickLookFrame(_ panel: QLPreviewPanel) {
        guard !isApplyingQuickLookFrame else { return }
        lockQuickLookSize(panel)

        let size = AppPreferences.quickLookSize
        let visible = (panel.screen ?? screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var origin = NSPoint(x: frame.maxX + 12, y: frame.maxY - size.height)
        if origin.x + size.width > visible.maxX {
            origin.x = frame.minX - size.width - 12
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        let next = NSRect(origin: origin, size: size)
        if abs(panel.frame.width - next.width) < 1,
           abs(panel.frame.height - next.height) < 1,
           abs(panel.frame.minX - next.minX) < 1,
           abs(panel.frame.minY - next.minY) < 1 {
            return
        }
        isApplyingQuickLookFrame = true
        panel.setFrame(next, display: true)
        isApplyingQuickLookFrame = false
    }

    private func reloadQuickLookIfVisible() {
        guard isPresentingQuickLook || isQuickLookVisible, let item = model.selectedItem else { return }
        do {
            let url = try QuickLookPreviewFile.makeURL(for: item)
            previewItem = ClipboardQuickLookItem(url: url, title: String(localized: "panel.preview.title"))
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.delegate = self
            panel.dataSource = self
            lockQuickLookSize(panel)
            watchQuickLookResize(panel)
            panel.reloadData()
            constrainQuickLook(panel)
        } catch {
            print("[NeatPaste] 切换条目后无法刷新系统预览：\(error.localizedDescription)")
        }
    }

    private func watchQuickLookResize(_ panel: QLPreviewPanel) {
        stopWatchingQuickLookResize()
        quickLookResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.performOnMain {
                guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
                self?.applyQuickLookFrame(panel)
            }
        }
    }

    private func stopWatchingQuickLookResize() {
        if let quickLookResizeObserver {
            NotificationCenter.default.removeObserver(quickLookResizeObserver)
            self.quickLookResizeObserver = nil
        }
    }

    private func makeChromeView(_ hostingView: NSHostingView<HistoryPanelView>) -> NSView {
        let frame = NSRect(origin: .zero, size: AppPreferences.panelSize)
        if #available(macOS 26.0, *) {
            let glass = PanelGlassView(frame: frame, cornerRadius: AppPreferences.panelCornerRadius)
            glass.autoresizingMask = [.width, .height]
            glass.clipsToBounds = true
            glass.contentView = hostingView
            return glass
        }

        let effect = NSVisualEffectView(frame: frame)
        effect.autoresizingMask = [.width, .height]
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = AppPreferences.panelCornerRadius
        effect.layer?.masksToBounds = true
        effect.addSubview(hostingView)
        hostingView.frame = effect.bounds
        hostingView.autoresizingMask = [.width, .height]
        return effect
    }
}

/// 面板关掉后，双击的第二下会落到下面正在输入的窗口。用一块透明挡板吃掉这一下。
@MainActor
private final class ClickThroughEater {
    private var panel: NSPanel?
    private var workItem: DispatchWorkItem?

    func cover(_ frame: NSRect, duration: TimeInterval) {
        cancel()
        let shield = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        shield.isOpaque = false
        shield.backgroundColor = .clear
        shield.hasShadow = false
        shield.level = .screenSaver
        shield.ignoresMouseEvents = false
        shield.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        shield.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        shield.orderFrontRegardless()
        panel = shield

        let work = DispatchWorkItem { [weak self] in
            self?.cancel()
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.2), execute: work)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 整窗通透玻璃。公开 API 只有 regular/clear，要去掉压暗层需探测私有属性；探不到就静默跳过。
@available(macOS 26.0, *)
private final class PanelGlassView: NSGlassEffectView {
    private typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void
    private let glassCornerRadius: CGFloat

    init(frame frameRect: NSRect, cornerRadius: CGFloat) {
        glassCornerRadius = cornerRadius
        super.init(frame: frameRect)
        applyClearGlass()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持通过归档创建玻璃底板")
    }

    override func layout() {
        super.layout()
        cornerRadius = glassCornerRadius
        applyClearGlass()
    }

    private func applyClearGlass() {
        style = .clear
        tintColor = .clear
        setPrivateIntegerProperty("variant", value: 2)
        setPrivateIntegerProperty("scrimState", value: 0)
        setPrivateIntegerProperty("subduedState", value: 0)
    }

    private func setPrivateIntegerProperty(_ key: String, value: Int) {
        let selectorNames = [
            "set_\(key):",
            "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        ]
        guard let selectorName = selectorNames.first(where: {
            responds(to: NSSelectorFromString($0))
        }) else {
            return
        }
        let selector = NSSelectorFromString(selectorName)
        let implementation = method(for: selector)
        let setter = unsafeBitCast(implementation, to: IntegerSetter.self)
        setter(self, selector, value)
    }
}

/// 系统预览成为焦点后，按键不会回到历史列表。预览打开期间用临时热键收空格、Esc 和上下键。
/// 热键只响按下/抬起各一次，按住不会连发；上下键必须接到按住连走，不能只走一步。
@MainActor
private final class PreviewDismissHotkey {
    var onDismiss: (@MainActor () -> Void)?
    var onMove: (@MainActor (Int) -> Void)?
    var onMoveEnd: (@MainActor (Int) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func install() {
        remove()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    let paramStatus = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard paramStatus == noErr, hotKeyID.signature == OSType(0x4E50_5156) else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let trap = Unmanaged<PreviewDismissHotkey>.fromOpaque(userData).takeUnretainedValue()
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        trap.release(id: hotKeyID.id)
                    } else {
                        trap.fire(id: hotKeyID.id)
                    }
                    return noErr
                },
                Int(buffer.count),
                buffer.baseAddress,
                selfPtr,
                &handler
            )
        }
        guard status == noErr else { return }

        register(UInt32(kVK_Space), id: 1)
        register(UInt32(kVK_Escape), id: 2)
        register(UInt32(kVK_UpArrow), id: 3)
        register(UInt32(kVK_DownArrow), id: 4)
    }

    func remove() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func register(_ keyCode: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E50_5156), id: id)
        let status = RegisterEventHotKey(keyCode, 0, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        }
    }

    nonisolated private func fire(id: UInt32) {
        Task { @MainActor in
            switch id {
            case 1, 2:
                onDismiss?()
            case 3:
                onMove?(-1)
            case 4:
                onMove?(1)
            default:
                break
            }
        }
    }

    nonisolated private func release(id: UInt32) {
        Task { @MainActor in
            switch id {
            case 3:
                onMoveEnd?(-1)
            case 4:
                onMoveEnd?(1)
            default:
                break
            }
        }
    }
}
