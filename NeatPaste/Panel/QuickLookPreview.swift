import AppKit
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// 把一条历史写成系统 Quick Look 能打开的临时文件。不改原始格式，只选最能代表该条的一种落地方式。
nonisolated enum QuickLookPreviewFile: Sendable {
    private static let directoryName = "NeatPasteQuickLook"

    nonisolated static func makeURL(for item: HistoryItem) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 与列表缩略图同一优先级：旁路与内联图片优先于 public.file-url，避免 stale 文件地址把预览带成文本。
        // 旁路 blob 文件名是 sha256、无扩展名，Quick Look 靠扩展名选预览器，直接返回会导致图片被当文本。
        // 必须拷贝到带图片扩展名的临时文件再返回。
        if let external = item.preferredExternalImageURL() {
            let ext = Self.externalImageExtension(for: item)
            let dest = directory.appendingPathComponent("\(item.id.uuidString).\(ext)")
            // 同一 UUID 扩展名可能变化（如类型推断修正），先清掉旧的同名不同扩展名残留再拷贝，保证新鲜。
            if dest.path != external.path {
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: external, to: dest)) != nil {
                    return dest
                }
            } else {
                return external
            }
        }

        if item.hasImage, let image = imagePayload(in: item.payloads) {
            return try writeImage(image, itemID: item.id, directory: directory)
        }

        if item.hasImage,
           let root = item.payloadDirectoryURL,
           !item.externalPayloadTypes.isEmpty {
            let vault = PayloadVault(rootURL: root)
            if let materialized = try? vault.materialize(
                itemID: item.id,
                inline: item.payloads,
                externalTypes: item.externalPayloadTypes
            ),
               let image = imagePayload(in: materialized) {
                return try writeImage(image, itemID: item.id, directory: directory)
            }
        }

        if let fileURL = existingFileURL(in: item) {
            if !item.hasImage || isImageFile(at: fileURL) {
                return fileURL
            }
        }

        if let rtf = item.payloads["public.rtf"], !rtf.isEmpty {
            let url = directory.appendingPathComponent("\(item.id.uuidString).rtf")
            try rtf.write(to: url, options: .atomic)
            return url
        }

        if let html = item.payloads["public.html"], !html.isEmpty {
            let url = directory.appendingPathComponent("\(item.id.uuidString).html")
            try html.write(to: url, options: .atomic)
            return url
        }

        let url = directory.appendingPathComponent("\(item.id.uuidString).txt")
        try item.plainText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated static func existingFileURL(in item: HistoryItem) -> URL? {
        guard let data = item.payloads["public.file-url"] else { return nil }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw), url.isFileURL else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    nonisolated static func isImageFile(at url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.conforms(to: .image) {
            return true
        }
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image) {
            return true
        }
        return false
    }

    nonisolated static func imagePayload(in payloads: [String: Data]) -> (data: Data, fileExtension: String)? {
        let candidates: [(String, String)] = [
            ("public.png", "png"),
            ("public.jpeg", "jpg"),
            ("public.jpg", "jpg"),
            ("public.tiff", "tiff"),
            ("public.heic", "heic"),
            ("public.gif", "gif"),
            ("public.image", "png")
        ]
        for (type, fileExtension) in candidates {
            if let data = payloads[type], !data.isEmpty {
                return (data, fileExtension)
            }
        }
        for (type, data) in payloads where PasteboardCapture.isImageType(type) && !data.isEmpty {
            return (data, fileExtension(forImageType: type))
        }
        return nil
    }

    /// 旁路图片的类型推断扩展名，与 PayloadVault.preferredImageURL 同一优先级，保证拷贝后的扩展名与实际字节对应。
    nonisolated static func externalImageExtension(for item: HistoryItem) -> String {
        for type in HistoryItem.preferredImageTypes {
            if item.externalPayloadTypes.contains(type) || item.types.contains(type) {
                return fileExtension(forImageType: type)
            }
        }
        for type in item.externalPayloadTypes where PasteboardCapture.isImageType(type) {
            return fileExtension(forImageType: type)
        }
        for type in item.types where PasteboardCapture.isImageType(type) {
            return fileExtension(forImageType: type)
        }
        return "png"
    }

    nonisolated static func fileExtension(forImageType type: String) -> String {
        let lowered = type.lowercased()
        if lowered.contains("jpeg") || lowered.contains("jpg") { return "jpg" }
        if lowered.contains("tiff") { return "tiff" }
        if lowered.contains("heic") || lowered.contains("heif") { return "heic" }
        if lowered.contains("gif") { return "gif" }
        if lowered.contains("png") { return "png" }
        return "png"
    }

    private static func writeImage(
        _ image: (data: Data, fileExtension: String),
        itemID: UUID,
        directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent("\(itemID.uuidString).\(image.fileExtension)")
        try image.data.write(to: url, options: .atomic)
        return url
    }
}

/// 系统 Quick Look 条目。标题给预览窗用，URL 指向临时文件或原文件。
nonisolated final class ClipboardQuickLookItem: NSObject, QLPreviewItem, @unchecked Sendable {
    nonisolated let previewItemURL: URL
    nonisolated let previewItemTitle: String

    nonisolated init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}
