import Foundation

nonisolated enum ClipboardContentIdentity: Hashable, Sendable {
    case fingerprint(String)
}
