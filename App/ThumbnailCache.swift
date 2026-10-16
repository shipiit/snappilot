import AppKit
import AVFoundation
import SnapCore

/// Small, downsampled previews for gallery, collection, picker and Recent tiles.
/// Decoding happens off the main thread; the cache is capped so browsing the whole library
/// can't grow memory without bound (macOS also purges it under memory pressure).
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    /// Longest side in pixels — sharp on Retina for tiles up to ~320 pt wide.
    static let tileSize = 640

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 120 * 1_048_576
        return cache
    }()

    /// A cached preview, or nil if it still needs loading.
    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    /// Load (or reuse) a preview for an image or video file.
    func thumbnail(for url: URL, isVideo: Bool = false) async -> NSImage? {
        if let hit = cached(url) { return hit }
        let image: CGImage? = isVideo
            ? await Self.videoFrame(url)
            : await Task.detached(priority: .utility) { Thumbnail.make(at: url, maxPixelSize: Self.tileSize) }.value
        guard let image else { return nil }
        let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        cache.setObject(preview, forKey: url as NSURL, cost: Thumbnail.byteCost(of: image))
        return preview
    }

    /// Drop a stale preview after the file was edited or replaced.
    func invalidate(_ url: URL) { cache.removeObject(forKey: url as NSURL) }

    private static func videoFrame(_ url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: tileSize, height: tileSize)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        return try? await generator.image(at: CMTime(seconds: max(0, seconds / 2), preferredTimescale: 600)).image
    }
}
