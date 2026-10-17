import AppKit
import QuartzCore

/// Fast, no-bounce motion for a frequently used overlay.
/// Frame (real window resize, never scale) and window + content fade run in one
/// group so the glass grows from the caret droplet without popping in opaque
/// or popping out at the end. Keep dismiss shorter than appear.
enum PanelMotion: Sendable {
    /// Perceptual duration: frequent shortcut, settle before it feels like a wait.
    nonisolated static let appearDuration: TimeInterval = 0.18
    /// Exit can be shorter than enter; get out of the way.
    nonisolated static let dismissDuration: TimeInterval = 0.12
    nonisolated static let reducedDuration: TimeInterval = 0.08

    /// Cubic-bezier control points shared by the animator timing functions
    /// and the manual anchored stepper (which must use the same easing so
    /// alpha and size stay together without an animator proxy).
    /// Appear uses a standard ease-out cubic: brisk but visibly progressive.
    /// A more front-loaded curve turns any first-tick delay into a whole-panel
    /// teleport (measured: 77%+ of growth in one frame), so keep early velocity
    /// bounded.
    nonisolated static let appearControlPoints = (x1: 0.215, y1: 0.61, x2: 0.355, y2: 1.0)
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
