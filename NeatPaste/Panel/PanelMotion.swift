import AppKit
import QuartzCore

/// Fast, no-bounce motion for a frequently used overlay.
/// The stepper resizes the real window (never a scale transform) and keeps the
/// caret-adjacent edges pinned. Opacity is not animated per frame: the panel
/// stays fully opaque so the glass and its shadow are not recomposited every
/// tick. Keep dismiss shorter than appear.
enum PanelMotion: Sendable {
    /// Perceptual duration: frequent shortcut, settle before it feels like a wait.
    nonisolated static let appearDuration: TimeInterval = 0.18
    /// Exit can be shorter than enter; get out of the way.
    nonisolated static let dismissDuration: TimeInterval = 0.12
    nonisolated static let reducedDuration: TimeInterval = 0.08

    /// Cubic-bezier control points shared by the animator timing functions
    /// and the manual anchored stepper (which must use the same easing without
    /// an animator proxy). Opacity is not part of the curve.
    /// Appear uses a standard ease-in-out: the fastest section sits in the
    /// middle, so a single dropped vsync cannot double or triple the height
    /// step. The previous strong ease-out put over half the growth in the
    /// first 30 ms; one missed 120 Hz frame there jumped 66–131 pt and read
    /// as vertical judder.
    nonisolated static let appearControlPoints = (x1: 0.4, y1: 0.0, x2: 0.2, y2: 1.0)
    nonisolated static let dismissControlPoints = (x1: 0.4, y1: 0.0, x2: 1.0, y2: 1.0)

    static var appearTiming: CAMediaTimingFunction {
        let c = appearControlPoints
        return CAMediaTimingFunction(controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2))
    }

    static var dismissTiming: CAMediaTimingFunction {
        let c = dismissControlPoints
        return CAMediaTimingFunction(controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2))
    }

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
