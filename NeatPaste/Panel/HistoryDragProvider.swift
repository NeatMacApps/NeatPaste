import AppKit
import Foundation
import UniformTypeIdentifiers

/// 把一条历史组装成向外拖的 NSItemProvider（访达、备忘录等）。
/// 渲染行时不做任何 IO；图片与文本文件在对方真正索取时才于 loadHandler 里落盘。
/// 优先级与缩略图/预览一致：旁路与内联图片优先于 public.file-url，避免 stale 文件地址把图片拖成文本。
nonisolated enum HistoryDragProvider: Sendable {
    private static let directoryName = "NeatPasteDrag"

    nonisolated static func provider(
        for item: HistoryItem,
        materialize: @escaping @Sendable (UUID) async -> [String: Data]
    ) -> NSItemProvider? {
        if item.hasImage {
            return imageProvider(for: item, materialize: materialize)
        }
        if let fileURL = QuickLookPreviewFile.existingFileURL(in: item) {
            let provider = NSItemProvider(object: fileURL as NSURL)
            provider.suggestedName = fileURL.lastPathComponent
            return provider
        }
        guard !item.plainText.isEmpty else { return nil }
        return textProvider(text: item.plainText)
    }

    // MARK: - 图片

    private static func imageProvider(
        for item: HistoryItem,
        materialize: @escaping @Sendable (UUID) async -> [String: Data]
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        let itemID = item.id
        let inline = item.payloads
        let externalTypes = item.externalPayloadTypes
        let ext = QuickLookPreviewFile.externalImageExtension(for: item)
        let contentType = UTType(filenameExtension: ext) ?? .png
        provider.suggestedName = dragFileName(title: item.plainText, extension: ext)

        provider.registerDataRepresentation(
            forTypeIdentifier: contentType.identifier,
            visibility: .all
        ) { completion in
            Task {
                if let bytes = await imageBytes(
                    itemID: itemID, inline: inline,
                    externalTypes: externalTypes, materialize: materialize
                ) {
                    completion(bytes, nil)
                } else {
                    completion(nil, DragStageError.noImage)
                }
            }
            return nil
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            visibility: .all
        ) { completion in
            Task {
                do {
                    let url = try await stagedImageURL(
                        itemID: itemID, inline: inline, externalTypes: externalTypes,
                        fileExtension: ext, materialize: materialize
                    )
                    completion(url, true, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private static func imageBytes(
        itemID: UUID,
        inline: [String: Data],
        externalTypes: [String],
        materialize: @escaping @Sendable (UUID) async -> [String: Data]
    ) async -> Data? {
        if let image = QuickLookPreviewFile.imagePayload(in: inline) {
            return image.data
        }
        guard !externalTypes.isEmpty else { return nil }
        let full = await materialize(itemID)
        return QuickLookPreviewFile.imagePayload(in: full)?.data
    }

    private static func stagedImageURL(
        itemID: UUID,
        inline: [String: Data],
        externalTypes: [String],
        fileExtension: String,
        materialize: @escaping @Sendable (UUID) async -> [String: Data]
    ) async throws -> URL {
        guard let bytes = await imageBytes(
            itemID: itemID, inline: inline,
            externalTypes: externalTypes, materialize: materialize
        ) else {
            throw DragStageError.noImage
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(itemID.uuidString).\(fileExtension)")
        try bytes.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 文本

    private static func textProvider(text: String) -> NSItemProvider {
        let provider = NSItemProvider(object: text as NSString)
        let fileName = dragFileName(title: text, extension: "txt")
        provider.suggestedName = fileName
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(directoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(fileName)
                try text.write(to: url, atomically: true, encoding: .utf8)
                completion(url, true, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    // MARK: - 文件名

    private static func dragFileName(title: String, extension ext: String) -> String {
        var stem = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = stem.components(separatedBy: .newlines).first {
            stem = firstLine
        }
        if stem.isEmpty || HistoryText.isMachineGeneratedName(stem) {
            stem = "NeatPaste"
        }
        stem = stem.replacingOccurrences(of: "/", with: "_")
        if stem.count > 80 {
            stem = String(stem.prefix(80))
        }
        return "\(stem).\(ext)"
    }
}

nonisolated enum DragStageError: Error, Sendable {
    case noImage
}
