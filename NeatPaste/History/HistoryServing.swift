import Foundation

nonisolated protocol HistoryServing: Sendable {
    func items() async -> [HistoryItem]
    func search(_ query: String) async -> [HistoryItem]
    func ingest(_ snapshot: PasteboardSnapshot) async
    func delete(id: UUID) async
    func sweepExpired(olderThan: Date) async
    /// 组装粘贴/预览所需的全量载荷（含旁路文件）。
    func materializePayloads(id: UUID) async -> [String: Data]
}
