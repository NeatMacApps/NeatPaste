import CryptoKit
import Foundation

/// 大载荷旁路目录：图片与超大非图片块落盘，内存列表只留元数据与小载荷。
nonisolated struct PayloadVault: Sendable {
    static let inlineByteLimit = 64 * 1024

    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func alongsideHistoryJSON(_ historyURL: URL) -> PayloadVault {
        PayloadVault(rootURL: historyURL.deletingLastPathComponent().appendingPathComponent("payloads", isDirectory: true))
    }

    static func shouldExternalize(type: String, data: Data) -> Bool {
        PasteboardCapture.isImageType(type) || data.count > inlineByteLimit
    }

    func itemDirectory(for itemID: UUID) -> URL {
        rootURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
    }

    /// 把该外置的载荷写入旁路目录；相同字节只存一份。返回应留在内存/JSON 的内联载荷与外置类型名列表。
    func spill(itemID: UUID, payloads: [String: Data]) throws -> (inline: [String: Data], externalTypes: [String]) {
        var inline: [String: Data] = [:]
        var externalTypes: [String] = []
        var hashToBlobName: [String: String] = [:]
        var typeToBlob: [String: String] = [:]

        let directory = itemDirectory(for: itemID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (type, data) in payloads {
            guard !data.isEmpty else { continue }
            if Self.shouldExternalize(type: type, data: data) {
                let digest = Self.sha256Hex(data)
                let blobName: String
                if let existing = hashToBlobName[digest] {
                    blobName = existing
                } else {
                    blobName = digest
                    let blobURL = directory.appendingPathComponent(blobName)
                    if !FileManager.default.fileExists(atPath: blobURL.path) {
                        try data.write(to: blobURL, options: .atomic)
                    }
                    hashToBlobName[digest] = blobName
                }
                typeToBlob[type] = blobName
                externalTypes.append(type)
            } else {
                inline[type] = data
            }
        }

        externalTypes.sort()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let encoded = try JSONEncoder().encode(typeToBlob)
        try encoded.write(to: manifestURL, options: .atomic)
        return (inline, externalTypes)
    }

    func materialize(itemID: UUID, inline: [String: Data], externalTypes: [String]) throws -> [String: Data] {
        var result = inline
        guard !externalTypes.isEmpty else { return result }

        let directory = itemDirectory(for: itemID)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let typeToBlob: [String: String]
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            typeToBlob = decoded
        } else {
            typeToBlob = [:]
        }

        for type in externalTypes {
            if let blob = typeToBlob[type] {
                let url = directory.appendingPathComponent(blob)
                if let data = try? Data(contentsOf: url), !data.isEmpty {
                    result[type] = data
                    continue
                }
            }
            let fallback = directory.appendingPathComponent(Self.sanitizedFileName(type))
            if let data = try? Data(contentsOf: fallback), !data.isEmpty {
                result[type] = data
            }
        }
        return result
    }

    func remove(itemID: UUID) {
        let directory = itemDirectory(for: itemID)
        try? FileManager.default.removeItem(at: directory)
    }

    /// 缩略图 / Quick Look 优先用的外置图片文件，不读进内存。
    func preferredImageURL(itemID: UUID, types: [String]) -> URL? {
        let directory = itemDirectory(for: itemID)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let typeToBlob = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONDecoder().decode([String: String].self, from: $0)
        } ?? [:]

        for type in HistoryItem.preferredImageTypes where types.contains(type) || typeToBlob[type] != nil {
            if let blob = typeToBlob[type] {
                let url = directory.appendingPathComponent(blob)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        for type in types where PasteboardCapture.isImageType(type) {
            if let blob = typeToBlob[type] {
                let url = directory.appendingPathComponent(blob)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sanitizedFileName(_ type: String) -> String {
        type
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

nonisolated enum HistoryFingerprint: Sendable {
    static func make(hasImage: Bool, payloads: [String: Data], plainText: String) -> String {
        if hasImage, let image = HistoryItem.preferredImageData(from: payloads) {
            return "img:" + PayloadVault.sha256Hex(image)
        }
        if let data = payloads["public.file-url"],
           let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return "file:" + raw
        }
        if !plainText.isEmpty {
            return "text:" + plainText
        }
        let stable = payloads
            .filter { key, value in
                !value.isEmpty
                    && !key.hasPrefix("dyn.")
                    && !key.lowercased().contains("webkit")
                    && !key.lowercased().contains("chromium")
            }
            .sorted { $0.key < $1.key }
        var hasher = SHA256()
        for (key, value) in stable {
            hasher.update(data: Data(key.utf8))
            hasher.update(data: value)
        }
        return "payloads:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
