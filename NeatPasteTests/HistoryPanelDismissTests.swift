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
