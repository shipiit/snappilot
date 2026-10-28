@preconcurrency import CoreImage
import CoreGraphics

/// How a blurred region hides what's under it.
public enum RedactStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case pixelate, blur, solid
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum RedactRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Pixel-block size that makes text unreadable: at least 10 px (a third of a typical text
    /// line), growing with the region so large areas are hidden too.
    public static func blockSize(for region: CGSize) -> CGFloat {
        min(64, max(10, min(region.width, region.height) / 3))
    }

    /// Gaussian radius that smears text into unreadable shapes.
    public static func blurRadius(for region: CGSize) -> CGFloat {
        min(40, max(10, min(region.width, region.height) / 3))
    }

    /// The redacted pixels for `rect` (top-left origin, pixels) of `image`, same size as the
    /// rect. Solid uses `solidColor`. Returns nil for an empty or off-image rect.
    public static func render(_ image: CGImage, rect: CGRect, style: RedactStyle,
                              solidColor: CGColor = CGColor(gray: 0.1, alpha: 1)) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = rect.intersection(bounds).integral
        guard r.width >= 1, r.height >= 1, let region = image.cropping(to: r) else { return nil }
        if style == .solid { return solidFill(size: r.size, color: solidColor) }
        if style == .pixelate { return mosaic(region, block: blockSize(for: r.size)) }

        let input = CIImage(cgImage: region)
        let output: CIImage?
        switch style {
        case .blur:
            // Clamp first so the edges blur into neighbouring pixels instead of fading to clear.
            output = input.clampedToExtent().applyingGaussianBlur(sigma: blurRadius(for: r.size))
        case .pixelate, .solid:
            output = nil
        }
        guard let output else { return nil }
        return context.createCGImage(output.cropped(to: input.extent), from: input.extent)
    }

    /// Averaged mosaic: every block becomes the exact mean of its pixels. (CIPixellate samples
    /// one pixel per block, which can leave text strokes as solid black-and-white blocks.)
    private static func mosaic(_ region: CGImage, block: CGFloat) -> CGImage? {
        let w = region.width, h = region.height, size = max(1, Int(block))
        guard let ctx = bitmap(width: w, height: h), let data = ctx.data else { return nil }
        ctx.draw(region, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rowBytes = ctx.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: rowBytes * h)
        for by in stride(from: 0, to: h, by: size) {
            for bx in stride(from: 0, to: w, by: size) {
                let yEnd = min(by + size, h), xEnd = min(bx + size, w)
                var sum = [Int](repeating: 0, count: 4)
                for y in by..<yEnd { for x in bx..<xEnd { for c in 0..<4 { sum[c] += Int(px[y * rowBytes + x * 4 + c]) } } }
                let count = (yEnd - by) * (xEnd - bx)
                let mean = sum.map { UInt8($0 / count) }
                for y in by..<yEnd { for x in bx..<xEnd { for c in 0..<4 { px[y * rowBytes + x * 4 + c] = mean[c] } } }
            }
        }
        return ctx.makeImage()
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func solidFill(size: CGSize, color: CGColor) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(color)
        ctx.fill(CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}
