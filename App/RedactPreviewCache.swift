import CoreGraphics
import Foundation
import SnapCore

/// Rendered redactions for the live editor canvas, so moving or redrawing doesn't
/// recompute every blur on every frame.
@MainActor
enum RedactPreviewCache {
    private static let cache: NSCache<NSString, CGImageBox> = {
        let cache = NSCache<NSString, CGImageBox>()
        cache.countLimit = 64
        return cache
    }()

    static func image(base: CGImage, rect: CGRect, style: RedactStyle) -> CGImage? {
        let r = rect.integral
        let key = "\(ObjectIdentifier(base).hashValue)|\(r.minX),\(r.minY),\(r.width),\(r.height)|\(style.rawValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        guard let image = RedactRenderer.render(base, rect: r, style: style) else { return nil }
        cache.setObject(CGImageBox(image), forKey: key)
        return image
    }

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}
