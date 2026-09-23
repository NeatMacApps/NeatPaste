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

    static var appearTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.22, 1)
    }

    static var dismissTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
    }

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
