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
    // Vsync-locked manual motion state. The window frame is stepped on every
    // display vsync (CADisplayLink) with a Task fallback that only drives ticks
    // while the link is stalled (headless tests), so pacing never judders from
    // a runloop timer beating against the display refresh.
    private var motionLink: CADisplayLink?
    private var motionFallbackTask: Task<Void, Never>?
    private var motionStartTime: CFTimeInterval = 0
    private var motionFrom = NSRect.zero
    private var motionTo = NSRect.zero
    private var motionPinsToTop = true
    private var motionDuration: TimeInterval = 0
    private var motionIsAppearing = true
    private var motionControlPoints = PanelMotion.appearControlPoints
    private var motionGenerationAtStart = 0
    private var motionDone = true
    private var motionCompletion: (@MainActor () -> Void)?
    private var motionLinkTickCount = 0
    /// Wall time when the display link last delivered. Stall detection must not
    /// compare against the link's vsync timestamp: that timestamp is older than
    /// the callback wall time by a variable latency, and mixing the two clocks
    /// made the fallback fire between two vsyncs.
    private var motionLastLinkWallTime: CFTimeInterval = 0
    private var motionLinkHasFired = false
    /// True once the fallback has taken over because the link never arrived (or
    /// stalled). From then on link ticks are ignored, so the animation is driven
    /// by exactly one clock.
    private var motionFallbackOwnsClock = false
    private var motionCreatedAt: CFTimeInterval = 0
    /// Progress already rendered; never decreases, so an out-of-order timestamp
    /// cannot make the window shrink and re-grow inside one expansion.
    private var motionRenderedProgress: Double = 0
    private var motionLastFrameDuration: CFTimeInterval = 1.0 / 60.0
    /// False until the first vsync tick after ordering the panel front. The
    /// motion clock starts on that tick, not at setup: a cold first frame can
    /// take tens of milliseconds, and charging that to the eased curve made the
    /// first presented frame jump to most of the final size.
    private var motionAwaitingFirstTick = true

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

    /// Settles list content while still ordered out, so reload churn (row
    /// insertion, scroll reset, thumbnail decode) lands invisibly before the
    /// first visible animation frame instead of swimming inside the growing glass.
    func prepareForShow() {
        contentPin?.needsLayout = true
        contentPin?.layoutSubtreeIfNeeded()
    }

    func showPanel(placement: PanelAnchor.Placement) {
        clickThroughEater?.cancel()
        clickThroughEater = nil
        isDismissing = false
        ignoresMouseEvents = false
        cancelMotionTask()
        motionGeneration += 1
        let generation = motionGeneration
        let targetFrame = Self.windowAlignedRect(placement.frame)
        // Derive the point-like seed from the snapped target so the shared edges
        // (left + caret-adjacent) are exactly equal, not just close.
        let seedLength = min(PanelAnchor.seedLength, targetFrame.width, targetFrame.height)
        let targetSeed = NSRect(
            x: targetFrame.minX,
            y: placement.pinsContentToTop ? targetFrame.maxY - seedLength : targetFrame.minY,
            width: seedLength,
            height: seedLength)
        let snappedPlacement = PanelAnchor.Placement(
            frame: targetFrame, seed: targetSeed, pinsContentToTop: placement.pinsContentToTop)
        currentPlacement = snappedPlacement
        contentPin?.pinsToTop = snappedPlacement.pinsContentToTop
        unlockSizeForMotion()

        let resumeFromCurrent = isVisible
        let startFrame: NSRect
        if !resumeFromCurrent {
            startFrame = targetSeed
            if PanelMotion.prefersReducedMotion {
                applyMotionFrame(targetFrame)
                // Reduced motion keeps a short fade; the stepper itself does not.
                hostingView?.alphaValue = 0
                alphaValue = 0
            } else {
                applyMotionFrame(startFrame)
            }
        } else {
            startFrame = frame
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
                context.allowsImplicitAnimation = false
                animator().alphaValue = 1
                hostingView?.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                self?.performOnMain {
                    guard let self, generation == self.motionGeneration else { return }
                    self.lockSizeAfterMotion(targetFrame)
                }
            }
            return
        }

        if resumeFromCurrent {
            // Already visible (e.g. re-anchor while open): still drive through
            // the anchored stepper so a shared edge never lerps independently.
            startManualMotion(
                from: startFrame, to: targetFrame,
                pinsToTop: snappedPlacement.pinsContentToTop,
                duration: PanelMotion.appearDuration, isAppearing: true,
                controlPoints: PanelMotion.appearControlPoints,
                generation: generation) { [weak self] in
                    self?.performOnMain {
                        guard let self, generation == self.motionGeneration else { return }
                        self.lockSizeAfterMotion(targetFrame)
                    }
                }
            return
        }

        startManualMotion(
            from: startFrame, to: targetFrame,
            pinsToTop: snappedPlacement.pinsContentToTop,
            duration: PanelMotion.appearDuration, isAppearing: true,
            controlPoints: PanelMotion.appearControlPoints,
            generation: generation) { [weak self] in
                self?.performOnMain {
                    guard let self, generation == self.motionGeneration else { return }
                    self.lockSizeAfterMotion(targetFrame)
                }
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
            cancelMotionTask()
            finishHide()
            return
        }
        if isDismissing {
            return
        }

        isDismissing = true
        ignoresMouseEvents = true
        cancelMotionTask()
        motionGeneration += 1
        let generation = motionGeneration
        unlockSizeForMotion()

        // Paste injects ⌘V immediately after hide. Stop taking keys now;
        // the glass can still recede visually.
        if isKeyWindow {
            resignKey()
        }

        let pinsToTop = currentPlacement?.pinsContentToTop ?? true
        let fromFrame = Self.windowAlignedRect(frame)
        let seedLength = min(PanelAnchor.seedLength, fromFrame.width, fromFrame.height)
        // Shrink back into the same caret-adjacent corner we grew from,
        // derived from the current frame so the shared edges stay exact.
        let seed = NSRect(
            x: fromFrame.minX,
            y: pinsToTop ? fromFrame.maxY - seedLength : fromFrame.minY,
            width: seedLength,
            height: seedLength
        )

        if PanelMotion.prefersReducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMotion.reducedDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                context.allowsImplicitAnimation = false
                animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.performOnMain {
                    guard let self, generation == self.motionGeneration else { return }
                    self.finishHide()
                }
            }
            return
        }

        startManualMotion(
            from: fromFrame, to: seed,
            pinsToTop: pinsToTop,
            duration: PanelMotion.dismissDuration, isAppearing: false,
            controlPoints: PanelMotion.dismissControlPoints,
            generation: generation) { [weak self] in
                self?.performOnMain {
                    guard let self, generation == self.motionGeneration else { return }
                    self.finishHide()
                }
            }
    }

    override func resignKey() {
        super.resignKey()
        if isDismissing || !isVisible { return }
        if isPresentingQuickLook || isQuickLookVisible { return }
        hidePanel()
    }

    private func unlockSizeForMotion() {
        minSize = NSSize(width: PanelAnchor.seedLength, height: PanelAnchor.seedLength)
        maxSize = NSSize(width: 10_000, height: 10_000)
    }

    private func lockSizeAfterMotion(_ frame: NSRect) {
        cancelMotionTask()
        applyMotionFrame(frame)
        minSize = AppPreferences.panelSize
        maxSize = AppPreferences.panelSize
        alphaValue = 1
        hostingView?.alphaValue = 1
        contentPin?.needsLayout = true
    }

    private func finishHide() {
        cancelMotionTask()
        hostingView?.alphaValue = 1
        alphaValue = 1
        minSize = AppPreferences.panelSize
        maxSize = AppPreferences.panelSize
        ignoresMouseEvents = false
        orderOut(nil)
        isDismissing = false
    }

    // MARK: - Anchored vsync motion
    //
    // `animator().setFrame` animates a window's origin and size as separate
    // Core Animation properties. Even when the seed and the target share the
    // caret-adjacent edges (left + top for downward, left + bottom for upward),
    // the two tweens interpolate independently with per-frame display rounding,
    // so `origin + size` wobbles by fractions of a point. That is the
    // vertical jitter on downward expansion and the occasional horizontal shimmer.
    // The animator group also enables implicit animations for descendant layers,
    // so SwiftUI/glass layers lag one frame behind the window.
    //
    // This stepper interpolates width/height plus the *fixed* edges with a single
    // eased progress value, derives the origin from the fixed edges every tick
    // (so shared edges are exactly constant), aligns to native screen points, and sets
    // frames synchronously with all implicit actions disabled. Ticks are driven
    // by the display vsync (CADisplayLink);
    // a Task fallback only steps while the link is stalled, so a runloop timer
    // never beats against the refresh and reads as judder. Real window resize is
    // preserved (no scaling).

    private func cancelMotionTask() {
        if let motionLink {
            motionLink.invalidate()
            self.motionLink = nil
        }
        motionFallbackTask?.cancel()
        motionFallbackTask = nil
        motionCompletion = nil
        motionDone = true
    }

    /// AppKit quantizes native window origins and sizes to whole screen points,
    /// even on Retina displays. A half-point fixed edge alternates by one point
    /// when origin and size are rounded independently during the resize.
    static func windowAlignedRect(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX.rounded(.down), y: rect.minY.rounded(.down),
            width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// Cubic-bezier easing: solve x(t) = progress for t, return y(t).
    /// Internal (not private) so motion-curve regressions can pin it in tests.
    static func easedProgress(
        _ x: Double,
        c1x: Double, c1y: Double, c2x: Double, c2y: Double
    ) -> Double {
        func sampleX(_ t: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t
        }
        func sampleY(_ t: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t
        }
        func sampleDX(_ t: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * c1x + 6 * u * t * (c2x - c1x) + 3 * t * t * (1 - c2x)
        }
        var t = x
        for _ in 0..<8 {
            let err = sampleX(t) - x
            if abs(err) < 1e-6 { return sampleY(t) }
            let d = sampleDX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
            t = min(max(t, 0), 1)
        }
        var lo = 0.0
        var hi = 1.0
        t = x
        while hi - lo > 1e-6 {
            if sampleX(t) < x {
                lo = t
            } else {
                hi = t
            }
            t = (lo + hi) / 2
        }
        return sampleY(t)
    }

    static func interpolatedMotionFrame(
        from: NSRect, to: NSRect, pinsToTop: Bool, progress: Double
    ) -> NSRect {
        let p = CGFloat(progress)
        let width = from.width + (to.width - from.width) * p
        let height = from.height + (to.height - from.height) * p
        let minX = from.minX + (to.minX - from.minX) * p
        let snappedWidth = width.rounded()
        let snappedHeight = height.rounded()
        let snappedMinX = minX.rounded()
        if pinsToTop {
            let maxY = from.maxY + (to.maxY - from.maxY) * p
            let snappedMaxY = maxY.rounded()
            return NSRect(x: snappedMinX, y: snappedMaxY - snappedHeight, width: snappedWidth, height: snappedHeight)
        } else {
            let minY = from.minY + (to.minY - from.minY) * p
            let snappedMinY = minY.rounded()
            return NSRect(x: snappedMinX, y: snappedMinY, width: snappedWidth, height: snappedHeight)
        }
    }

    private func applyMotionFrame(_ frame: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.allowsImplicitAnimation = false
        // Geometry only. Redraw in the normal display cycle: forcing
        // displayIfNeeded on every 120 Hz tick made the glass re-render on
        // the main thread and caused 16–51 ms gaps between vsyncs.
        setFrame(frame, display: false)
        alphaValue = 1
        hostingView?.alphaValue = 1
        NSAnimationContext.endGrouping()
        CATransaction.commit()
    }

    private func startManualMotion(
        from: NSRect, to: NSRect,
        pinsToTop: Bool,
        duration: TimeInterval,
        isAppearing: Bool,
        controlPoints: (x1: Double, y1: Double, x2: Double, y2: Double),
        generation: Int,
        completion: @MainActor @escaping () -> Void
    ) {
        cancelMotionTask()
        let fromSnapped = Self.windowAlignedRect(from)
        let toSnapped = Self.windowAlignedRect(to)
        // Zero-duration (or reduced-motion callers) must still land exactly.
        guard duration > 0.001 else {
            applyMotionFrame(toSnapped)
            completion()
            return
        }
        motionFrom = fromSnapped
        motionTo = toSnapped
        motionPinsToTop = pinsToTop
        motionDuration = duration
        motionIsAppearing = isAppearing
        motionControlPoints = controlPoints
        motionGenerationAtStart = generation
        motionDone = false
        motionCompletion = completion
        motionLinkTickCount = 0
        motionLastLinkWallTime = 0
        motionLinkHasFired = false
        motionFallbackOwnsClock = false
        motionCreatedAt = CACurrentMediaTime()
        motionRenderedProgress = 0
        motionLastFrameDuration = 1.0 / 60.0
        motionAwaitingFirstTick = true
        motionStartTime = 0
        model.isMotionActive = true

        let link = displayLink(target: self, selector: #selector(motionLinkFired(_:)))
        motionLink = link
        link.add(to: .main, forMode: .common)

        // Fallback for environments without vsync (headless tests): only steps
        // while the link has not fired recently, so it never double-drives.
        motionFallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while true {
                try? await Task.sleep(for: .milliseconds(8))
                if Task.isCancelled { break }
                guard !self.motionDone, generation == self.motionGeneration else { break }
                let now = CACurrentMediaTime()
                if !self.motionFallbackOwnsClock {
                    if self.motionLinkHasFired {
                        // The link is healthy: never co-drive it. Only take over
                        // after it has been silent for a full stall window.
                        guard now - self.motionLastLinkWallTime > 0.12 else { continue }
                    } else {
                        // Give the link a chance to start; a headless context
                        // gets the fallback after this window.
                        guard now - self.motionCreatedAt > 0.15 else { continue }
                    }
                    self.motionFallbackOwnsClock = true
                }
                if self.motionTick(now: now) { break }
            }
        }
    }

    @objc private nonisolated func motionLinkFired(_ link: CADisplayLink) {
        // CADisplayLink is not Sendable: only its timestamps cross into the actor.
        let timestamp = link.timestamp
        let frameDuration = link.duration
        performOnMain { self.motionLinkFiredOnMain(timestamp: timestamp, frameDuration: frameDuration) }
    }

    private func motionLinkFiredOnMain(timestamp: CFTimeInterval, frameDuration: CFTimeInterval) {
        guard !motionDone, motionGenerationAtStart == motionGeneration else { return }
        guard !motionFallbackOwnsClock else { return }
        motionLinkTickCount += 1
        motionLinkHasFired = true
        motionLastLinkWallTime = CACurrentMediaTime()
        if frameDuration > 0 {
            motionLastFrameDuration = frameDuration
        }
        _ = motionTick(now: timestamp)
    }

    /// Applies one eased frame. Returns true when the motion reached its end.
    /// Progress is a pure function of wall time. Capping it per tick made a
    /// 120 Hz display render ten 40 px steps (~80 ms total) instead of the
    /// intended 180 ms ease-out, and let the fallback Task spend two steps in
    /// one refresh; both read as vertical jitter at every invocation.
    @discardableResult
    private func motionTick(now: CFTimeInterval) -> Bool {
        guard !motionDone, motionGenerationAtStart == motionGeneration else { return true }
        if motionAwaitingFirstTick {
            // Start the clock on the first presented frame: setup time and a
            // cold first render must not be charged to the easing curve. Do not
            // render progress 0 here: a visible re-anchor would flash alpha 0.
            motionAwaitingFirstTick = false
            motionStartTime = now
            return false
        }
        let linear = min(max((now - motionStartTime) / motionDuration, 0), 1)
        let eased = Self.easedProgress(
            linear,
            c1x: motionControlPoints.x1, c1y: motionControlPoints.y1,
            c2x: motionControlPoints.x2, c2y: motionControlPoints.y2)
        // Monotonic floor: a timestamp from a different clock (or a hitch) must
        // never move the window backwards mid-motion.
        let progress = max(eased, motionRenderedProgress)
        motionRenderedProgress = progress
        let frame = Self.interpolatedMotionFrame(
            from: motionFrom, to: motionTo,
            pinsToTop: motionPinsToTop, progress: progress)
        applyMotionFrame(frame)
        if linear >= 1 {
            finalizeMotion(now: now)
            return true
        }
        return false
    }

    private func finalizeMotion(now: CFTimeInterval) {
        guard !motionDone, motionGenerationAtStart == motionGeneration else { return }
        motionDone = true
        if let motionLink {
            motionLink.invalidate()
            self.motionLink = nil
        }
        motionFallbackTask?.cancel()
        motionFallbackTask = nil
        applyMotionFrame(motionTo)
        model.isMotionActive = false
        // Anomaly-only telemetry: silent when pacing is healthy.
        let elapsed = now - motionStartTime
        if elapsed > motionDuration + 0.15 {
            NSLog(
                "[NeatPaste] panel motion slow: %.3fs wall vs %.3fs planned, %d vsync ticks",
                elapsed, motionDuration, CInt(motionLinkTickCount))
        } else if motionLinkTickCount > 0 {
            let expected = motionDuration / motionLastFrameDuration
            if Double(motionLinkTickCount) < expected * 0.5 {
                NSLog(
                    "[NeatPaste] panel motion dropped frames: %d vsync ticks vs %.0f expected (%.3fs)",
                    CInt(motionLinkTickCount), expected, motionDuration)
            }
        }
        guard let completion = motionCompletion else { return }
        motionCompletion = nil
        // Break any retain cycle only if no newer motion replaced us.
        completion()
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

/// Keeps list content at its real size while the glass window grows from a point.
final class PinnedContentHost: NSView {
    var pinsToTop = true {
        didSet { positionContent() }
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

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // The window animator resizes us before the next deferred layout pass.
        // Move the full-size content in the same frame so its screen anchor stays fixed.
        positionContent()
    }

    override func layout() {
        super.layout()
        positionContent()
    }

    private func positionContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
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
