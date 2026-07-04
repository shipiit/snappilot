import CoreGraphics

public enum ImageOps {
    /// Crop a CGImage to a pixel rect (clamped to bounds). Returns nil if empty.
    public static func crop(_ image: CGImage, to pixelRect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = pixelRect.intersection(bounds).integral
        guard r.width >= 1, r.height >= 1 else { return nil }
        return image.cropping(to: r)
    }

    /// Clamp a requested pixelate block size to a sane range (used by the redaction tool).
    public static func clampBlock(_ n: Int) -> Int { max(2, min(64, n)) }

    /// Scale a size down so its longest edge is at most `maxEdge`, preserving aspect.
    /// Returns the original size when it already fits. Used for thumbnails/previews.
    public static func fit(_ size: CGSize, maxEdge: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return size }
        let factor = maxEdge / longest
        return CGSize(width: (size.width * factor).rounded(),
                      height: (size.height * factor).rounded())
    }
}
