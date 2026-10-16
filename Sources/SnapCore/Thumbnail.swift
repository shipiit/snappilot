import CoreGraphics
import Foundation
import ImageIO

/// Downsampled image loading. Decoding a full Retina screenshot to fill a small tile costs
/// ~15 MB per tile once it's on screen; ImageIO can decode straight to the size we draw.
public enum Thumbnail {
    /// Decode `url` so its longest side is at most `maxPixelSize` (never upscaled).
    public static func make(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Bytes a decoded image occupies — used as its cache cost.
    public static func byteCost(of image: CGImage) -> Int { image.bytesPerRow * image.height }
}
