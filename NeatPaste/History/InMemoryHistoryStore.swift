import Foundation

actor InMemoryHistoryStore: HistoryServing {
    private var records: [HistoryItem]
    private let storageURL: URL?
    private let vault: PayloadVault?

    init(records: [HistoryItem] = [], storageURL: URL? = nil) {
        self.storageURL = storageURL
        self.vault = storageURL.map { PayloadVault.alongsideHistoryJSON($0) }
        if records.isEmpty, let storageURL {
            self.records = Self.load(from: storageURL, vault: self.vault)
        } else {
            let payloadRoot = self.vault?.rootURL
            self.records = records.map { item in
                HistoryItem(
                    id: item.id,
                    createdAt: item.createdAt,
                    plainText: item.plainText,
                    sourceBundleID: item.sourceBundleID,
                    hasImage: item.hasImage,
                    hasFilePromise: item.hasFilePromise,
                    types: item.types,
                    payloads: item.payloads,
                    externalPayloadTypes: item.externalPayloadTypes,
                    contentFingerprint: item.contentFingerprint,
                    payloadDirectoryURL: item.payloadDirectoryURL ?? payloadRoot
                )
            }.sorted { $0.createdAt > $1.createdAt }
        }
        var mutable = self.records
        _ = Self.dropExpired(from: &mutable, vault: self.vault)
        self.records = mutable
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
        let draft = snapshot.makeHistoryItem()
        let prepared = prepareForStorage(draft, fullPayloads: snapshot.payloads)

        let duplicates = records.filter { $0.contentIdentity == prepared.contentIdentity }
        for duplicate in duplicates {
            vault?.remove(itemID: duplicate.id)
        }
        records.removeAll { $0.contentIdentity == prepared.contentIdentity }
        records.insert(prepared, at: 0)
        _ = Self.dropExpired(from: &records, vault: vault)
        persist()
        NSLog(
            "[NeatPaste] 已收入一条剪贴板记录，类型数 %d，外置 %d，文本前缀 %@",
            snapshot.types.count,
            prepared.externalPayloadTypes.count,
            String(prepared.plainText.prefix(40)) as NSString
        )
    }

    func delete(id: UUID) async {
        vault?.remove(itemID: id)
        records.removeAll { $0.id == id }
        persist()
    }

    func sweepExpired(olderThan date: Date) async {
        let doomed = records.filter { $0.createdAt < date }
        for item in doomed {
            vault?.remove(itemID: item.id)
        }
        records.removeAll { $0.createdAt < date }
        persist()
    }

    func materializePayloads(id: UUID) async -> [String: Data] {
        guard let item = records.first(where: { $0.id == id }) else { return [:] }
        guard let vault, !item.externalPayloadTypes.isEmpty else {
            return item.payloads
        }
        do {
            return try vault.materialize(
                itemID: item.id,
                inline: item.payloads,
                externalTypes: item.externalPayloadTypes
            )
        } catch {
            NSLog("[NeatPaste] 旁路载荷读回失败：%@", error.localizedDescription)
            return item.payloads
        }
    }

    private func prepareForStorage(_ draft: HistoryItem, fullPayloads: [String: Data]) -> HistoryItem {
        guard let vault else {
            return HistoryItem(
                id: draft.id,
                createdAt: draft.createdAt,
                plainText: draft.plainText,
                sourceBundleID: draft.sourceBundleID,
                hasImage: draft.hasImage,
                hasFilePromise: draft.hasFilePromise,
                types: draft.types,
                payloads: fullPayloads,
                externalPayloadTypes: [],
                contentFingerprint: draft.contentFingerprint,
                payloadDirectoryURL: nil
            )
        }

        do {
            let spilled = try vault.spill(itemID: draft.id, payloads: fullPayloads)
            return HistoryItem(
                id: draft.id,
                createdAt: draft.createdAt,
                plainText: draft.plainText,
                sourceBundleID: draft.sourceBundleID,
                hasImage: draft.hasImage,
                hasFilePromise: draft.hasFilePromise,
                types: draft.types,
                payloads: spilled.inline,
                externalPayloadTypes: spilled.externalTypes,
                contentFingerprint: draft.contentFingerprint,
                payloadDirectoryURL: vault.rootURL
            )
        } catch {
            NSLog("[NeatPaste] 旁路写入失败，本条暂留内联：%@", error.localizedDescription)
            return HistoryItem(
                id: draft.id,
                createdAt: draft.createdAt,
                plainText: draft.plainText,
                sourceBundleID: draft.sourceBundleID,
                hasImage: draft.hasImage,
                hasFilePromise: draft.hasFilePromise,
                types: draft.types,
                payloads: fullPayloads,
                externalPayloadTypes: [],
                contentFingerprint: draft.contentFingerprint,
                payloadDirectoryURL: vault.rootURL
            )
        }
    }

    private func persist() {
        Self.write(records, to: storageURL)
    }

    @discardableResult
    private static func dropExpired(from records: inout [HistoryItem], vault: PayloadVault?) -> [UUID] {
        let cutoff = Date().addingTimeInterval(-AppPreferences.historyLifetime)
        let doomed = records.filter { $0.createdAt < cutoff }.map(\.id)
        for id in doomed {
            vault?.remove(itemID: id)
        }
        records.removeAll { $0.createdAt < cutoff }
        return doomed
    }

    private static func load(from url: URL, vault: PayloadVault?) -> [HistoryItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else {
            NSLog("[NeatPaste] 历史文件读不出，先按空列表启动")
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let persisted = try decoder.decode([PersistedHistoryRecord].self, from: data)
            let payloadRoot = vault?.rootURL
            var migrated: [HistoryItem] = []
            var didMigrate = false

            for record in persisted {
                var item = record.asHistoryItem(payloadDirectoryURL: payloadRoot)
                if let vault {
                    let needsSpill = item.payloads.contains { type, data in
                        PayloadVault.shouldExternalize(type: type, data: data)
                    }
                    if needsSpill {
                        let spilled = try vault.spill(itemID: item.id, payloads: item.payloads)
                        item = HistoryItem(
                            id: item.id,
                            createdAt: item.createdAt,
                            plainText: item.plainText,
                            sourceBundleID: item.sourceBundleID,
                            hasImage: item.hasImage,
                            hasFilePromise: item.hasFilePromise,
                            types: item.types.isEmpty ? Array(item.payloads.keys) + spilled.externalTypes : item.types,
                            payloads: spilled.inline,
                            externalPayloadTypes: Array(Set(item.externalPayloadTypes + spilled.externalTypes)).sorted(),
                            contentFingerprint: item.contentFingerprint,
                            payloadDirectoryURL: vault.rootURL
                        )
                        didMigrate = true
                    }
                }
                migrated.append(item)
            }

            let sorted = migrated.sorted { $0.createdAt > $1.createdAt }
            if didMigrate {
                write(sorted, to: url)
                NSLog("[NeatPaste] 已将历史大载荷外置迁移，条目 %d", sorted.count)
            }
            return sorted
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
            let persisted = records.map(PersistedHistoryRecord.from)
            let data = try encoder.encode(persisted)
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
