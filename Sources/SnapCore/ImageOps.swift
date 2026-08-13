import CoreGraphics
import CoreImage

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

    public static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    public static func rotatedRight(_ image: CGImage) -> CGImage? {
        let width = image.height, height = image.width
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width), y: 0)
        context.rotate(by: .pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    public static func flippedHorizontal(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Replace a top-left-origin image region with a solid color.
    public static func filling(_ image: CGImage, rect: CGRect,
                               color: CGColor = CGColor(gray: 0.96, alpha: 1)) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bottomLeft = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY,
                                width: rect.width, height: rect.height)
        context.setFillColor(color); context.fill(bottomLeft)
        return context.makeImage()
    }

    /// Average color around a region, useful for reconstructing the background behind
    /// OCR text. The expanded sample reduces the influence of the glyphs themselves.
    public static func surroundingColor(_ image: CGImage, rect: CGRect) -> CGColor {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let sample = rect.insetBy(dx: -max(4, rect.height * 0.35),
                                  dy: -max(3, rect.height * 0.25)).intersection(bounds)
        let ciImage = CIImage(cgImage: image)
        guard !sample.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage") else { return CGColor(gray: 1, alpha: 1) }
        // Core Image uses bottom-left coordinates; editor rectangles use top-left.
        let ciRect = CGRect(x: sample.minX, y: CGFloat(image.height) - sample.maxY,
                            width: sample.width, height: sample.height)
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciRect), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return CGColor(gray: 1, alpha: 1) }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.cacheIntermediates: false]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return CGColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}
