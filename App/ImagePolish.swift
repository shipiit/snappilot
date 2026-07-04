import AppKit
import CoreGraphics

/// Wraps an image in a padded gradient background with rounded corners + a drop shadow —
/// the "beautiful screenshot" look for sharing.
enum ImagePolish {
    static func frame(_ image: CGImage, padding: CGFloat = 64, radius: CGFloat = 18) -> CGImage {
        let w = image.width, h = image.height
        let outW = w + Int(padding * 2), outH = h + Int(padding * 2)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ns = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let ctx = ns.cgContext

        // Background gradient.
        let colors = [NSColor(srgbRed: 0.36, green: 0.42, blue: 0.95, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.62, green: 0.35, blue: 0.90, alpha: 1).cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: outH), end: CGPoint(x: outW, y: 0), options: [])
        }

        let rect = CGRect(x: padding, y: padding, width: CGFloat(w), height: CGFloat(h))
        let rounded = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Drop shadow (cast by an opaque rounded shape).
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12),
                      blur: 34, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.addPath(rounded); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
        ctx.restoreGState()

        // The image, clipped to rounded corners.
        ctx.saveGState()
        ctx.addPath(rounded); ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage ?? image
    }
}
