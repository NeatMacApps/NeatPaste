import Foundation

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
