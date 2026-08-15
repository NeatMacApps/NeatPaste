import Foundation

nonisolated protocol HistoryServing: Sendable {
    func items() async -> [HistoryItem]
    func search(_ query: String) async -> [HistoryItem]
    func ingest(_ snapshot: PasteboardSnapshot) async
    func delete(id: UUID) async
    func sweepExpired(olderThan: Date) async
}

nonisolated struct HistoryItem: Identifiable, Sendable, Hashable {
    let id: UUID
    let createdAt: Date
    let plainText: String
    let sourceBundleID: String?
    let hasImage: Bool
}

nonisolated struct PasteboardSnapshot: Sendable {
    let changeCount: Int
    let types: [String]
    let payloads: [String: Data]
    let sourceBundleID: String?
}

nonisolated enum HistorySearch: Sendable {
    nonisolated static func matches(_ item: HistoryItem, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return item.plainText.localizedCaseInsensitiveContains(trimmed)
    }
}
