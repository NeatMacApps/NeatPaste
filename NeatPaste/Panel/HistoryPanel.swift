import AppKit
import MacKitOverlay
import QuartzCore
import QuickLookUI
import SwiftUI

@MainActor
final class HistoryPanel: NSPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let model: HistoryPanelModel
    private var hostingView: NSHostingView<HistoryPanelView>?
    private var keyMonitor: Any?
    private let outsideClickMonitor = OutsideClickMonitor()
    /// 菜单栏本图标等点击后仍应由原入口处理开关，不能当成「点外面」。
    var additionalKeptFrames: () -> [NSRect] = { [] }
    private var previewItem: ClipboardQuickLookItem?
    private var isPresentingQuickLook = false
    private var isApplyingQuickLookFrame = false
    private var quickLookResizeObserver: NSObjectProtocol?
    private let dismissHotkey = PreviewDismissHotkey()
    private let arrowRepeat = ArrowKeyRepeat()
    private var clickThroughEater: ClickThroughEater?
    private var contentPin: PinnedContentHost?
    private var currentPlacement: PanelAnchor.Placement?
    private var motionGeneration = 0
    private var isDismissing = false

    /// Visible and not in the middle of shrinking away. Hotkey toggle uses this.
    var isPresented: Bool { isVisible && !isDismissing }

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
        if let frame {
            showPanel(placement: PanelAnchor.placement(frame: frame, preferredRect: nil))
        } else {
            showPanel(placement: PanelAnchor.placement(for: AppPreferences.panelSize))
        }
    }

    func showPanel(placement: PanelAnchor.Placement) {
        clickThroughEater?.cancel()
        clickThroughEater = nil
        isDismissing = false
        ignoresMouseEvents = false
        motionGeneration += 1
        let generation = motionGeneration
        currentPlacement = placement
        contentPin?.pinsToTop = placement.pinsContentToTop
        unlockSizeForMotion()

        let resumeFromCurrent = isVisible
        if !resumeFromCurrent {
            if PanelMotion.prefersReducedMotion {
                setFrame(placement.frame, display: true)
            } else {
                setFrame(placement.seed, display: true)
            }
            hostingView?.alphaValue = 0
            alphaValue = PanelMotion.prefersReducedMotion ? 0 : 1
        }

        orderFrontRegardless()
        makeKey()
        installKeyMonitor()
        installOutsideClickMonitor()
        contentPin?.needsLayout = true
        contentPin?.layoutSubtreeIfNeeded()

        if PanelMotion.prefersReducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMotion.reducedDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
                hostingView?.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                guard let self, generation == self.motionGeneration else { return }
                self.lockSizeAfterMotion(placement.frame)
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMotion.appearDuration
            context.timingFunction = PanelMotion.appearTiming
            context.allowsImplicitAnimation = true
            animator().setFrame(placement.frame, display: true)
            hostingView?.animator().alphaValue = 1
            alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self, generation == self.motionGeneration else { return }
            self.lockSizeAfterMotion(placement.frame)
        }
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

        guard isVisible else {
            finishHide()
            return
        }
        if isDismissing {
            return
        }

        isDismissing = true
        ignoresMouseEvents = true
        motionGeneration += 1
        let generation = motionGeneration
        unlockSizeForMotion()

        // Paste injects ⌘V immediately after hide. Stop taking keys now;
        // the glass can still recede visually.
        if isKeyWindow {
            resignKey()
        }

        let seed = currentPlacement?.seed ?? NSRect(
            x: frame.midX - PanelAnchor.seedLength / 2,
            y: frame.midY - PanelAnchor.seedLength / 2,
            width: PanelAnchor.seedLength,
            height: PanelAnchor.seedLength
        )

        if PanelMotion.prefersReducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMotion.reducedDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, generation == self.motionGeneration else { return }
                self.finishHide()
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMotion.dismissDuration
            context.timingFunction = PanelMotion.dismissTiming
            context.allowsImplicitAnimation = true
            animator().setFrame(seed, display: true)
            hostingView?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, generation == self.motionGeneration else { return }
            self.finishHide()
        }
    }

    override func resignKey() {
        super.resignKey()
        if isDismissing || !isVisible { return }
        if isPresentingQuickLook || isQuickLookVisible { return }
        hidePanel()
    }

    private func unlockSizeForMotion() {
        minSize = NSSize(width: 8, height: 8)
        maxSize = NSSize(width: 10_000, height: 10_000)
    }

    private func lockSizeAfterMotion(_ frame: NSRect) {
        setFrame(frame, display: true)
        minSize = AppPreferences.panelSize
        maxSize = AppPreferences.panelSize
        alphaValue = 1
        hostingView?.alphaValue = 1
        contentPin?.needsLayout = true
    }

    private func finishHide() {
        hostingView?.alphaValue = 1
        alphaValue = 1
        minSize = AppPreferences.panelSize
        maxSize = AppPreferences.panelSize
        ignoresMouseEvents = false
        orderOut(nil)
        isDismissing = false
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
        // 点到别的应用时本窗口往往不会失焦：浮层并不把本应用切到前台，底下那个应用本来就是前台。
        // 必须靠全局按下监听立刻收起，否则会挡屏幕。不要用「本应用失活」来关，否则一打开就会被关掉。
        outsideClickMonitor.panelFrame = { [weak self] in self?.frame ?? .zero }
        outsideClickMonitor.isPanelVisible = { [weak self] in self?.isVisible ?? false }
        outsideClickMonitor.isOwnWindow = { [weak self] window in
            guard let self else { return false }
            if window === self { return true }
            if let preview = QLPreviewPanel.shared(), window === preview { return true }
            return Self.isContextMenuWindow(window)
        }
        outsideClickMonitor.additionalKeptFrames = { [weak self] in
            guard let self else { return [] }
            var kept = self.additionalKeptFrames()
            if let preview = QLPreviewPanel.shared(), preview.isVisible {
                kept.append(preview.frame)
            }
            return kept
        }
        outsideClickMonitor.onOutsideClick = { [weak self] in self?.hidePanel() }
        outsideClickMonitor.install()
    }

    private func removeOutsideClickMonitor() {
        outsideClickMonitor.remove()
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
        let pin = PinnedContentHost(hosted: hostingView, fullSize: AppPreferences.panelSize)
        pin.frame = frame
        pin.autoresizingMask = [.width, .height]
        contentPin = pin
        if #available(macOS 26.0, *) {
            let glass = PanelGlassView(frame: frame, cornerRadius: AppPreferences.panelCornerRadius)
            glass.autoresizingMask = [.width, .height]
            glass.clipsToBounds = true
            glass.contentView = pin
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
        effect.addSubview(pin)
        pin.frame = effect.bounds
        return effect
    }
}

/// Keeps list content at its real size while the glass window grows from a droplet.
private final class PinnedContentHost: NSView {
    var pinsToTop = true {
        didSet { needsLayout = true }
    }

    private let fullSize: NSSize
    private let hosted: NSView

    init(hosted: NSView, fullSize: NSSize) {
        self.hosted = hosted
        self.fullSize = fullSize
        super.init(frame: .zero)
        addSubview(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PinnedContentHost is not archived")
    }

    override func layout() {
        super.layout()
        if pinsToTop {
            hosted.frame = NSRect(
                x: 0,
                y: bounds.height - fullSize.height,
                width: fullSize.width,
                height: fullSize.height
            )
        } else {
            hosted.frame = NSRect(origin: .zero, size: fullSize)
        }
    }
}
