import AppKit
import Foundation
import ImageIO

nonisolated enum HistoryThumbnail: Sendable {
    static let side: CGFloat = 28
    private static let maxPixel = 56

    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    nonisolated static func image(for item: HistoryItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let made = makeImage(for: item) else { return nil }
        cache.setObject(made, forKey: key)
        return made
    }

    private static func makeImage(for item: HistoryItem) -> NSImage? {
        if let url = item.preferredExternalImageURL() {
            return downsample(url: url)
        }
        if let data = item.imageBytes() {
            return downsample(data: data)
        }
        if let url = QuickLookPreviewFile.existingFileURL(in: item) {
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
}
