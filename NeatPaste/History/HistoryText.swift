import AppKit
import Foundation

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
