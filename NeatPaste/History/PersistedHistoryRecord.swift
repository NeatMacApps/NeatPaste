import Foundation

/// 瘦 JSON 持久化形态。旧版只有 `payloads` 全量内联时由加载路径迁移。
nonisolated struct PersistedHistoryRecord: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let plainText: String
    let sourceBundleID: String?
    let hasImage: Bool
    let hasFilePromise: Bool
    let types: [String]
    let contentFingerprint: String
    let inlinePayloads: [String: Data]
    let externalPayloadTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id, createdAt, plainText, sourceBundleID, hasImage, hasFilePromise, types
        case contentFingerprint, inlinePayloads, externalPayloadTypes
        case payloads
    }

    init(
        id: UUID,
        createdAt: Date,
        plainText: String,
        sourceBundleID: String?,
        hasImage: Bool,
        hasFilePromise: Bool,
        types: [String],
        contentFingerprint: String,
        inlinePayloads: [String: Data],
        externalPayloadTypes: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.plainText = plainText
        self.sourceBundleID = sourceBundleID
        self.hasImage = hasImage
        self.hasFilePromise = hasFilePromise
        self.types = types
        self.contentFingerprint = contentFingerprint
        self.inlinePayloads = inlinePayloads
        self.externalPayloadTypes = externalPayloadTypes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        plainText = try container.decode(String.self, forKey: .plainText)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        hasImage = try container.decode(Bool.self, forKey: .hasImage)
        hasFilePromise = try container.decodeIfPresent(Bool.self, forKey: .hasFilePromise) ?? false
        types = try container.decodeIfPresent([String].self, forKey: .types) ?? []

        if let inline = try container.decodeIfPresent([String: Data].self, forKey: .inlinePayloads) {
            inlinePayloads = inline
            externalPayloadTypes = try container.decodeIfPresent([String].self, forKey: .externalPayloadTypes) ?? []
            contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
                ?? HistoryFingerprint.make(hasImage: hasImage, payloads: inline, plainText: plainText)
        } else {
            // 旧胖 JSON：全部在 payloads 里，加载后再外置迁移。
            let legacy = try container.decodeIfPresent([String: Data].self, forKey: .payloads) ?? [:]
            inlinePayloads = legacy
            externalPayloadTypes = []
            contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
                ?? HistoryFingerprint.make(hasImage: hasImage, payloads: legacy, plainText: plainText)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(plainText, forKey: .plainText)
        try container.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
        try container.encode(hasImage, forKey: .hasImage)
        try container.encode(hasFilePromise, forKey: .hasFilePromise)
        try container.encode(types, forKey: .types)
        try container.encode(contentFingerprint, forKey: .contentFingerprint)
        try container.encode(inlinePayloads, forKey: .inlinePayloads)
        try container.encode(externalPayloadTypes, forKey: .externalPayloadTypes)
    }

    func asHistoryItem(payloadDirectoryURL: URL?) -> HistoryItem {
        HistoryItem(
            id: id,
            createdAt: createdAt,
            plainText: plainText,
            sourceBundleID: sourceBundleID,
            hasImage: hasImage,
            hasFilePromise: hasFilePromise,
            types: types,
            payloads: inlinePayloads,
            externalPayloadTypes: externalPayloadTypes,
            contentFingerprint: contentFingerprint,
            payloadDirectoryURL: payloadDirectoryURL
        )
    }

    static func from(_ item: HistoryItem) -> PersistedHistoryRecord {
        PersistedHistoryRecord(
            id: item.id,
            createdAt: item.createdAt,
            plainText: item.plainText,
            sourceBundleID: item.sourceBundleID,
            hasImage: item.hasImage,
            hasFilePromise: item.hasFilePromise,
            types: item.types,
            contentFingerprint: item.contentFingerprint,
            inlinePayloads: item.payloads,
            externalPayloadTypes: item.externalPayloadTypes
        )
    }
}
