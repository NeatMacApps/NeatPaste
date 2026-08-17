import Foundation

actor InMemoryHistoryStore: HistoryServing {
    private var records: [HistoryItem]
    private let storageURL: URL?

    init(records: [HistoryItem] = [], storageURL: URL? = nil) {
        self.storageURL = storageURL
        if records.isEmpty, let storageURL {
            self.records = Self.load(from: storageURL)
        } else {
            self.records = records.sorted { $0.createdAt > $1.createdAt }
        }
        Self.dropExpired(from: &self.records)
        if storageURL != nil {
            Self.write(self.records, to: storageURL)
        }
    }

    /// 本机用户资料目录里的历史文件。重启后从这里读回 7 天内的记录。
    nonisolated static func defaultStorageURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeatPaste", isDirectory: true)
        return root.appendingPathComponent("history.json")
    }

    func items() async -> [HistoryItem] {
        records.sorted { $0.createdAt > $1.createdAt }
    }

    func search(_ query: String) async -> [HistoryItem] {
        let sorted = records.sorted { $0.createdAt > $1.createdAt }
        return sorted.filter { HistorySearch.matches($0, query: query) }
    }

    func ingest(_ snapshot: PasteboardSnapshot) async {
        let item = snapshot.makeHistoryItem()
        records.removeAll { $0.contentIdentity == item.contentIdentity }
        records.insert(item, at: 0)
        Self.dropExpired(from: &records)
        persist()
        NSLog("[NeatPaste] 已收入一条剪贴板记录，类型数 %d，文本前缀 %@", snapshot.types.count, String(item.plainText.prefix(40)) as NSString)
    }

    func delete(id: UUID) async {
        records.removeAll { $0.id == id }
        persist()
    }

    func sweepExpired(olderThan date: Date) async {
        records.removeAll { $0.createdAt < date }
        persist()
    }

    private func persist() {
        Self.write(records, to: storageURL)
    }

    private static func dropExpired(from records: inout [HistoryItem]) {
        let cutoff = Date().addingTimeInterval(-AppPreferences.historyLifetime)
        records.removeAll { $0.createdAt < cutoff }
    }

    private static func load(from url: URL) -> [HistoryItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else {
            NSLog("[NeatPaste] 历史文件读不出，先按空列表启动")
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([HistoryItem].self, from: data)
            return loaded.sorted { $0.createdAt > $1.createdAt }
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.appendingPathExtension("corrupt-\(stamp)")
            do {
                try fm.moveItem(at: url, to: backup)
                NSLog("[NeatPaste] 历史文件损坏，已挪到 %@：%@", backup.lastPathComponent, error.localizedDescription)
            } catch {
                NSLog("[NeatPaste] 历史文件损坏且备份失败：%@", error.localizedDescription)
            }
            return []
        }
    }

    private static func write(_ records: [HistoryItem], to url: URL?) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[NeatPaste] 历史写入失败：%@", error.localizedDescription)
        }
    }

    static func fixtureItems(now: Date = Date()) -> [HistoryItem] {
        [
            HistoryItem(
                id: UUID(),
                createdAt: now,
                plainText: "Hello from NeatPaste — latest clipboard note.",
                sourceBundleID: "com.apple.TextEdit",
                hasImage: false,
                payloads: ["public.utf8-plain-text": Data("Hello from NeatPaste — latest clipboard note.".utf8)]
            ),
            HistoryItem(
                id: UUID(),
                createdAt: now.addingTimeInterval(-90),
                plainText: "第二段中文剪贴内容，用来验证不区分大小写筛选。",
                sourceBundleID: "com.apple.Safari",
                hasImage: false,
                payloads: ["public.utf8-plain-text": Data("第二段中文剪贴内容，用来验证不区分大小写筛选。".utf8)]
            ),
            HistoryItem(
                id: UUID(),
                createdAt: now.addingTimeInterval(-180),
                plainText: "A screenshot of the desktop dock",
                sourceBundleID: "com.apple.screencapture",
                hasImage: true,
                types: ["public.png"],
                payloads: ["public.utf8-plain-text": Data("A screenshot of the desktop dock".utf8)]
            )
        ]
    }
}
