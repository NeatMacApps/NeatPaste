import AppKit
import Foundation
import ImageIO

nonisolated enum HistoryThumbnail: Sendable {
    static let side: CGFloat = 28
    private static let maxPixel = 56

    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()
    private static let decodes = DecodeRegistry()

    /// Cache-only lookup for a row body. Never touches the payload files, so
    /// SwiftUI evaluation cannot block on a large image.
    nonisolated static func cachedImage(for item: HistoryItem) -> NSImage? {
        cache.object(forKey: item.id.uuidString as NSString)
    }

    /// Decode one thumbnail off the main thread. Concurrent callers for the
    /// same item await the same decode. The image is only handed back through
    /// the cache so no NSImage crosses an isolation boundary.
    nonisolated static func loadImage(for item: HistoryItem) async {
        let key = item.id.uuidString
        if cache.object(forKey: key as NSString) != nil { return }
        let task = decodes.task(for: item.id) {
            guard cache.object(forKey: key as NSString) == nil else { return }
            guard let made = makeImage(for: item) else { return }
            cache.setObject(made, forKey: key as NSString)
        }
        await task.value
    }

    /// Warm the newest rows before the panel opens. Decoding stays off the main
    /// thread, so this only removes first-open placeholders.
    nonisolated static func prewarm(_ items: [HistoryItem], limit: Int = 12) {
        for item in items.prefix(limit) where item.hasImage {
            let key = item.id.uuidString
            if cache.object(forKey: key as NSString) != nil { continue }
            _ = decodes.task(for: item.id) {
                guard cache.object(forKey: key as NSString) == nil else { return }
                guard let made = makeImage(for: item) else { return }
                cache.setObject(made, forKey: key as NSString)
            }
        }
    }

    private static func makeImage(for item: HistoryItem) -> NSImage? {
        if let url = item.preferredExternalImageURL() {
            return downsample(url: url)
        }
        if let data = item.imageBytes() {
            return downsample(data: data)
        }
        if item.hasImage,
           let root = item.payloadDirectoryURL,
           !item.externalPayloadTypes.isEmpty,
           let materialized = try? PayloadVault(rootURL: root).materialize(
               itemID: item.id,
               inline: item.payloads,
               externalTypes: item.externalPayloadTypes
           ),
           let data = HistoryItem.preferredImageData(from: materialized) {
            return downsample(data: data)
        }
        if let url = QuickLookPreviewFile.existingFileURL(in: item),
           QuickLookPreviewFile.isImageFile(at: url) {
            return downsample(url: url)
        }
        return nil
    }

    private static func downsample(data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source)
    }

    private static func downsample(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source)
    }

    private static func thumbnail(from source: CGImageSource) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// One in-flight decode per item. A row and the prewarm pass can ask for
    /// the same image at the same time; both wait for the same task instead of
    /// decoding a multi-megabyte source twice.
    private final class DecodeRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [UUID: Task<Void, Never>] = [:]

        func task(for id: UUID, operation: @escaping @Sendable () -> Void) -> Task<Void, Never> {
            lock.lock()
            defer { lock.unlock() }
            if let existing = tasks[id] { return existing }
            let task = Task.detached(priority: .utility) { operation() }
            tasks[id] = task
            Task.detached { [weak self] in
                await task.value
                self?.remove(id)
            }
            return task
        }

        private func remove(_ id: UUID) {
            lock.lock()
            tasks[id] = nil
            lock.unlock()
        }
    }
}
