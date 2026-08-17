import AppKit
import Foundation
import QuickLookUI

/// 把一条历史写成系统 Quick Look 能打开的临时文件。不改原始格式，只选最能代表该条的一种落地方式。
nonisolated enum QuickLookPreviewFile: Sendable {
    private static let directoryName = "NeatPasteQuickLook"

    nonisolated static func makeURL(for item: HistoryItem) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let fileURL = existingFileURL(in: item) {
            return fileURL
        }

        if item.hasImage, let image = imagePayload(in: item) {
            let url = directory.appendingPathComponent("\(item.id.uuidString).\(image.fileExtension)")
            try image.data.write(to: url, options: .atomic)
            return url
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

    nonisolated static func imagePayload(in item: HistoryItem) -> (data: Data, fileExtension: String)? {
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
            if let data = item.payloads[type], !data.isEmpty {
                return (data, fileExtension)
            }
        }
        for (type, data) in item.payloads where PasteboardCapture.isImageType(type) && !data.isEmpty {
            return (data, "png")
        }
        return nil
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
