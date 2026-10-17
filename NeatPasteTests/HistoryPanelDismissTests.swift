import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class HistoryPanelDismissTests: XCTestCase {
    func test_点在面板里不要关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        XCTAssertFalse(PanelDismissPolicy.shouldHide(click: KitPoint(x: 200, y: 200), keptFrames: [panel]))
    }

    func test_点在面板外要立刻关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        XCTAssertTrue(PanelDismissPolicy.shouldHide(click: KitPoint(x: 20, y: 20), keptFrames: [panel]))
    }

    func test_点在系统预览上不要关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        let preview = KitRect(x: 520, y: 220, width: 480, height: 360)
        XCTAssertFalse(PanelDismissPolicy.shouldHide(click: KitPoint(x: 700, y: 300), keptFrames: [panel, preview]))
    }

    func test_点在菜单栏本图标上不要关() {
        let panel = KitRect(x: 100, y: 100, width: 400, height: 480)
        let statusItem = KitRect(x: 1200, y: 870, width: 28, height: 22)
        XCTAssertFalse(PanelDismissPolicy.shouldHide(click: KitPoint(x: 1210, y: 880), keptFrames: [panel, statusItem]))
        XCTAssertTrue(PanelDismissPolicy.shouldHide(click: KitPoint(x: 1100, y: 880), keptFrames: [panel, statusItem]))
    }
}

final class HistoryPanelMotionTests: XCTestCase {
    @MainActor
    func testAnimatedWindowKeepsCaretEdgeAndContentTogether() async throws {
        let model = HistoryPanelModel(history: InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems()))
        await model.reload()
        let panel = HistoryPanel(model: model)
        defer { panel.orderOut(nil) }
        let glass = try XCTUnwrap(panel.contentView as? NSGlassEffectView)
        let pin = try XCTUnwrap(glass.contentView)
        let hosted = try XCTUnwrap(pin.subviews.first)
        let frame = NSRect(x: 200, y: 200, width: 320, height: 432)
        for top in [true, false] {
            panel.orderOut(nil)
            let seed = NSRect(x: frame.minX, y: top ? frame.maxY - 36 : frame.minY,
                              width: 36, height: 36)
            panel.showPanel(placement: PanelAnchor.Placement(frame: frame, seed: seed, pinsContentToTop: top))
            var heights: [CGFloat] = []
            for sample in 0..<30 {
                try await Task.sleep(for: .milliseconds(8))
                heights.append(panel.frame.height)
                let content = panel.convertToScreen(hosted.convert(hosted.bounds, to: nil))
                let edge = top ? frame.maxY : frame.minY
                XCTAssertEqual(top ? panel.frame.maxY : panel.frame.minY, edge, accuracy: 0.5)
                XCTAssertEqual(top ? content.maxY : content.minY, edge, accuracy: 0.5)
                // Horizontal edge must stay pinned too: the window grows rightward
                // from the caret, so minX (window + content) never moves.
                XCTAssertEqual(panel.frame.minX, frame.minX, accuracy: 0.5)
                XCTAssertEqual(content.minX, frame.minX, accuracy: 0.5)
                XCTAssertEqual(hosted.frame.size, AppPreferences.panelSize)
                let keys = hosted.layer?.animationKeys() ?? []
                XCTAssertFalse(keys.contains { $0.contains("position") || $0.contains("bounds") || $0.contains("frame") })
                if top, [0, 3, 6, 9, 15, 29].contains(sample),
                   let bitmap = glass.bitmapImageRepForCachingDisplay(in: glass.bounds) {
                    glass.cacheDisplay(in: glass.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                        attachment.name = "downward-\(sample)-height-\(Int(panel.frame.height))"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
            XCTAssertTrue(heights.contains { $0 > 36 && $0 < frame.height }, "Must sample an in-flight resize")
            print("Panel motion top=\(top), heights=\(heights)")
        }
    }

    @MainActor
    func testContentStaysPinnedDuringEveryResizeBeforeDeferredLayout() {
        let size = AppPreferences.panelSize
        let hosted = NSView(frame: .zero)
        let pin = PinnedContentHost(hosted: hosted, fullSize: size)
        pin.frame = NSRect(origin: .zero, size: size)
        pin.layoutSubtreeIfNeeded()

        hosted.wantsLayer = true
        // Resizing is synchronous; a later layout pass must not repair a stale frame.
        for height in [36.0, 84.5, 190.0, 320.5, 432.0, 190.0, 36.0] {
            pin.setFrameSize(NSSize(width: size.width, height: height))
            XCTAssertEqual(hosted.frame.maxY, height, accuracy: 0.001)
            XCTAssertEqual(hosted.frame.size, size)
            XCTAssertTrue(hosted.layer?.animationKeys()?.isEmpty ?? true)
        }

        // Switching above the caret pins to the bottom immediately, even without resize.
        pin.pinsToTop = false
        XCTAssertEqual(hosted.frame.minY, 0)
        for height in [84.5, 190.0, 432.0, 36.0] {
            pin.setFrameSize(NSSize(width: size.width, height: height))
            XCTAssertEqual(hosted.frame.minY, 0)
            XCTAssertEqual(hosted.frame.size, size)
        }
        pin.pinsToTop = true
        XCTAssertEqual(hosted.frame.maxY, 36)
    }
}

final class HistoryPanelMotionCurveTests: XCTestCase {
    @MainActor
    func testAppearCurveNeverFrontLoadsIntoTeleport() {
        let c = PanelMotion.appearControlPoints
        // At 10% wall time the eased progress must stay well below half:
        // the old (0.2, 0.9, 0.22, 1.0) curve mapped an early first-tick delay
        // into a whole-panel single-frame jump (measured 77%+ of growth in one
        // frame). This pins the replacement curve against re-front-loading.
        let early = HistoryPanel.easedProgress(0.1, c1x: c.x1, c1y: c.y1, c2x: c.x2, c2y: c.y2)
        XCTAssertLessThan(early, 0.45)
        XCTAssertGreaterThanOrEqual(early, 0)
        XCTAssertEqual(
            HistoryPanel.easedProgress(0, c1x: c.x1, c1y: c.y1, c2x: c.x2, c2y: c.y2),
            0, accuracy: 1e-9)
        XCTAssertEqual(
            HistoryPanel.easedProgress(1, c1x: c.x1, c1y: c.y1, c2x: c.x2, c2y: c.y2),
            1, accuracy: 1e-6)
    }

    @MainActor
    func testMotionSpanTracksWallClockInsteadOfTickCount() {
        let model = HistoryPanelModel(history: InMemoryHistoryStore(records: InMemoryHistoryStore.fixtureItems()))
        let panel = HistoryPanel(model: model)
        defer { panel.orderOut(nil) }
        let target = NSRect(x: 200, y: 200, width: 320, height: 432)
        let seed = NSRect(x: target.minX, y: target.maxY - 36, width: 36, height: 36)
        panel.showPanel(placement: PanelAnchor.Placement(
            frame: target, seed: seed, pinsContentToTop: true))

        // Sampling every ~8 ms for 240 ms: a wall-clock 0.18 s motion must
        // still be in flight for most of the samples. The per-tick 10 % cap
        // finished in ~10 ticks on a 120 Hz display (measured 7–9 samples),
        // which is exactly the staircase users saw.
        var heights: [CGFloat] = []
        let deadline = Date().addingTimeInterval(0.24)
        while Date() < deadline {
            heights.append(panel.frame.height)
            RunLoop.main.run(until: Date().addingTimeInterval(0.008))
        }
        let inFlight = heights.filter { $0 > 36.5 && $0 < target.height - 0.5 }
        XCTAssertGreaterThanOrEqual(
            inFlight.count, 12,
            "0.18 s motion must span the planned duration, not finish in ~10 ticks: \(heights)")
    }
}
