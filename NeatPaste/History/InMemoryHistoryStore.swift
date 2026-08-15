import Foundation

actor InMemoryHistoryStore: HistoryServing {
    private var records: [HistoryItem]

    init(records: [HistoryItem] = InMemoryHistoryStore.fixtureItems()) {
        self.records = records.sorted { $0.createdAt > $1.createdAt }
    }

    func items() async -> [HistoryItem] {
        records.sorted { $0.createdAt > $1.createdAt }
    }

    func search(_ query: String) async -> [HistoryItem] {
        let sorted = records.sorted { $0.createdAt > $1.createdAt }
        return sorted.filter { HistorySearch.matches($0, query: query) }
    }

    func ingest(_ snapshot: PasteboardSnapshot) async {
        let textType = "public.utf8-plain-text"
        let text = snapshot.payloads[textType].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let hasImage = snapshot.types.contains { type in
            type.contains("png") || type.contains("tiff") || type.contains("image") || type.contains("jpeg")
        }
        let item = HistoryItem(
            id: UUID(),
            createdAt: Date(),
            plainText: text,
            sourceBundleID: snapshot.sourceBundleID,
            hasImage: hasImage
        )
        records.insert(item, at: 0)
        print("[NeatPaste] 已收入一条剪贴板快照，类型数 \(snapshot.types.count)")
    }

    func delete(id: UUID) async {
        records.removeAll { $0.id == id }
    }

    func sweepExpired(olderThan date: Date) async {
        records.removeAll { $0.createdAt < date }
    }

    static func fixtureItems(now: Date = Date()) -> [HistoryItem] {
        [
            HistoryItem(
                id: UUID(),
                createdAt: now,
                plainText: "Hello from NeatPaste — latest clipboard note.",
                sourceBundleID: "com.apple.TextEdit",
                hasImage: false
            ),
            HistoryItem(
                id: UUID(),
                createdAt: now.addingTimeInterval(-90),
                plainText: "第二段中文剪贴内容，用来验证不区分大小写筛选。",
                sourceBundleID: "com.apple.Safari",
                hasImage: false
            ),
            HistoryItem(
                id: UUID(),
                createdAt: now.addingTimeInterval(-180),
                plainText: "A screenshot of the desktop dock",
                sourceBundleID: "com.apple.screencapture",
                hasImage: true
            )
        ]
    }
}
