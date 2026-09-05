import Foundation

nonisolated enum HistorySearch: Sendable {
    nonisolated static func matches(_ item: HistoryItem, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return item.plainText.localizedCaseInsensitiveContains(trimmed)
    }
}
