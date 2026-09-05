import Foundation

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
