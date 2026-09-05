import AppKit
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

nonisolated struct HistoryItem: Identifiable, Sendable, Hashable {
    static let preferredImageTypes = [
        "public.png",
        "public.jpeg",
        "public.jpg",
        "public.tiff",
        "public.heic",
        "public.gif",
        "public.image"
    ]

    let id: UUID
    let createdAt: Date
    let plainText: String
    let sourceBundleID: String?
    let hasImage: Bool
    let hasFilePromise: Bool
    let types: [String]
    /// 仅内联小载荷；图片与大块在旁路目录。
    let payloads: [String: Data]
    let externalPayloadTypes: [String]
    let contentFingerprint: String
    /// 本条外置文件所在 payloads 根目录（运行期解析用，不进 JSON）。
    let payloadDirectoryURL: URL?

    init(
        id: UUID,
        createdAt: Date,
        plainText: String,
        sourceBundleID: String?,
        hasImage: Bool,
        hasFilePromise: Bool = false,
        types: [String] = [],
        payloads: [String: Data] = [:],
        externalPayloadTypes: [String] = [],
        contentFingerprint: String? = nil,
        payloadDirectoryURL: URL? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.plainText = plainText
        self.sourceBundleID = sourceBundleID
        self.hasImage = hasImage
        self.hasFilePromise = hasFilePromise
        self.types = types
        self.payloads = payloads
        self.externalPayloadTypes = externalPayloadTypes
        self.payloadDirectoryURL = payloadDirectoryURL
        self.contentFingerprint = contentFingerprint
            ?? HistoryFingerprint.make(hasImage: hasImage, payloads: payloads, plainText: plainText)
    }

    /// 用来判断「用户眼里是不是同一条」。忽略来源应用和会随每次复制变掉的元数据。
    var contentIdentity: ClipboardContentIdentity {
        .fingerprint(contentFingerprint)
    }

    func imageBytes() -> Data? {
        Self.preferredImageData(from: payloads)
    }

    /// 旁路图片文件（优先），供缩略图与 Quick Look 直接打开。
    func preferredExternalImageURL() -> URL? {
        guard let root = payloadDirectoryURL, !externalPayloadTypes.isEmpty else { return nil }
        return PayloadVault(rootURL: root).preferredImageURL(itemID: id, types: types)
    }

    static func preferredImageData(from payloads: [String: Data]) -> Data? {
        for type in preferredImageTypes {
            if let data = payloads[type], !data.isEmpty {
                return data
            }
        }
        for (type, data) in payloads where PasteboardCapture.isImageType(type) && !data.isEmpty {
            return data
        }
        return nil
    }
}

nonisolated enum ClipboardContentIdentity: Hashable, Sendable {
    case fingerprint(String)
}

nonisolated struct PasteboardSnapshot: Sendable {
    let changeCount: Int
    let types: [String]
    let payloads: [String: Data]
    let sourceBundleID: String?
    let hasFilePromise: Bool

    init(
        changeCount: Int,
        types: [String],
        payloads: [String: Data],
        sourceBundleID: String?,
        hasFilePromise: Bool = false
    ) {
        self.changeCount = changeCount
        self.types = types
        self.payloads = payloads
        self.sourceBundleID = sourceBundleID
        self.hasFilePromise = hasFilePromise
    }

    func makeHistoryItem(id: UUID = UUID(), createdAt: Date = Date()) -> HistoryItem {
        let hasImage = types.contains(where: PasteboardCapture.isImageType)
        let plainText = HistoryText.plainText(from: payloads)
        return HistoryItem(
            id: id,
            createdAt: createdAt,
            plainText: plainText,
            sourceBundleID: sourceBundleID,
            hasImage: hasImage,
            hasFilePromise: hasFilePromise,
            types: types,
            payloads: payloads,
            contentFingerprint: HistoryFingerprint.make(hasImage: hasImage, payloads: payloads, plainText: plainText)
        )
    }
}

nonisolated enum HistorySearch: Sendable {
    nonisolated static func matches(_ item: HistoryItem, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return item.plainText.localizedCaseInsensitiveContains(trimmed)
    }
}

nonisolated enum HistoryText: Sendable {
    nonisolated static func plainText(from payloads: [String: Data]) -> String {
        let utf8Keys = [
            "public.utf8-plain-text",
            "NSStringPboardType",
            "public.plain-text"
        ]
        for key in utf8Keys {
            if let data = payloads[key], let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        if let data = payloads["public.utf16-plain-text"],
           let text = String(data: data, encoding: .utf16), !text.isEmpty {
            return text
        }
        if let data = payloads["public.rtf"],
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            let text = attributed.string
            if !text.isEmpty { return text }
        }
        if let data = payloads["public.html"],
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            let text = attributed.string
            if !text.isEmpty { return text }
        }
        if let data = payloads["public.file-url"],
           let raw = String(data: data, encoding: .utf8),
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url.lastPathComponent
        }
        return ""
    }

    /// 列表上给人看的标题。图片若只有系统临时文件名，就显示「图片」，不要把内部编号亮出来。
    static func listTitle(plainText: String, hasImage: Bool) -> String {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasImage, trimmed.isEmpty || isMachineGeneratedName(trimmed) {
            return String(localized: "panel.image.placeholder")
        }
        return trimmed
    }

    static func isMachineGeneratedName(_ text: String) -> Bool {
        let name = basename(of: text)
        guard !name.isEmpty else { return false }
        let stem = (name as NSString).deletingPathExtension
        let pattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}([_-][0-9A-Za-z]+)*$"#
        return stem.range(of: pattern, options: .regularExpression) != nil
    }

    private static func basename(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "file" {
            return url.lastPathComponent
        }
        if trimmed.contains("/") {
            return URL(fileURLWithPath: trimmed).lastPathComponent
        }
        return trimmed
    }
}

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
