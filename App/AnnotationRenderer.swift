import AppKit
import CoreImage
import CoreGraphics
import SnapCore

/// Parses "#RRGGBB" (optionally with alpha "#RRGGBBAA") into an NSColor.
func nsColor(fromHex hex: String) -> NSColor {
    var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if s.count == 6 { s += "FF" }
    guard s.count == 8, let v = UInt32(s, radix: 16) else { return .systemRed }
    return NSColor(srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
                   green: CGFloat((v >> 16) & 0xFF) / 255,
                   blue: CGFloat((v >> 8) & 0xFF) / 255,
                   alpha: CGFloat(v & 0xFF) / 255)
}

/// Convert an NSColor to "#RRGGBB".
func hexString(fromNSColor color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    return String(format: "#%02X%02X%02X",
                  Int(round(c.redComponent * 255)),
                  Int(round(c.greenComponent * 255)),
                  Int(round(c.blueComponent * 255)))
}

/// Flattens a base image + annotation layers into a single raster image.
/// Annotation coordinates are in the base image's **pixel** space, top-left origin.
enum AnnotationRenderer {
    private static let ciContext = CIContext()

    static func flatten(base: CGImage, doc: AnnotationDocument) -> CGImage {
        let w = base.width, h = base.height
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ns = NSGraphicsContext(bitmapImageRep: rep) else { return base }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let ctx = ns.cgContext
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        for a in doc.items { draw(a, imageHeight: h, base: base, ctx: ctx) }
        NSGraphicsContext.restoreGraphicsState()

        return rep.cgImage ?? base
    }

    /// Convert a top-left pixel rect (from start/end) into bottom-left drawing coords.
    private static func blRect(start: CGPoint, end: CGPoint, imageHeight h: Int) -> NSRect {
        let tl = selectionRect(from: start, to: end)
        return NSRect(x: tl.minX, y: CGFloat(h) - tl.maxY, width: tl.width, height: tl.height)
    }
    private static func flipY(_ p: CGPoint, _ h: Int) -> NSPoint { NSPoint(x: p.x, y: CGFloat(h) - p.y) }

    private static func draw(_ a: Annotation, imageHeight h: Int, base: CGImage, ctx: CGContext) {
        let color = nsColor(fromHex: a.colorHex).withAlphaComponent(a.opacity)
        color.set()
        let lw = CGFloat(a.thickness)
        let dash = a.lineStyle.dashPattern(width: a.thickness).map { CGFloat($0) }

        switch a.tool {
        case .line, .arrow:
            let s = flipY(a.start, h), e = flipY(a.end, h)
            strokePath(from: s, to: e, width: lw, dash: dash)
            let sz = a.arrowSize.scale
            drawHead(a.startHead, at: s, from: e, width: lw, sizeScale: sz, color: color)
            drawHead(a.endHead, at: e, from: s, width: lw, sizeScale: sz, color: color)
        case .rect:
            let p = NSBezierPath(rect: blRect(start: a.start, end: a.end, imageHeight: h))
            p.lineWidth = lw
            if a.filled { p.fill() } else { if !dash.isEmpty { p.setLineDash(dash, count: dash.count, phase: 0) }; p.stroke() }
        case .ellipse:
            let p = NSBezierPath(ovalIn: blRect(start: a.start, end: a.end, imageHeight: h))
            p.lineWidth = lw
            if a.filled { p.fill() } else { if !dash.isEmpty { p.setLineDash(dash, count: dash.count, phase: 0) }; p.stroke() }
        case .highlight:
            let r = blRect(start: a.start, end: a.end, imageHeight: h)
            color.withAlphaComponent(0.35 * a.opacity).set()
            NSBezierPath(rect: r).fill()
        case .pen:
            strokePath(from: flipY(a.start, h), to: flipY(a.end, h), width: lw)
        case .text:
            drawText(a.text, at: flipY(a.start, h), color: color, size: max(14, lw * 6))
        case .callout:
            drawCallout(a, imageHeight: h, color: color, lw: lw)
        case .step:
            drawStep(a.stepLabel, center: flipY(a.start, h), radius: max(14, lw * 5), color: color)
        case .blur:
            drawBlur(rectTL: selectionRect(from: a.start, to: a.end), imageHeight: h, base: base, ctx: ctx)
        case .stamp:
            let s = (a.text.isEmpty ? "⭐️" : a.text) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(24, lw * 12))]
            let center = flipY(a.start, h)
            let sz = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
        case .crop:
            break   // crop is applied to the base image itself, not drawn
        }
    }

    private static func drawCallout(_ a: Annotation, imageHeight h: Int, color: NSColor, lw: CGFloat) {
        let r = blRect(start: a.start, end: a.end, imageHeight: h)
        let bubble = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        color.setFill(); bubble.fill()
        let text = a.text.isEmpty ? "Callout" : a.text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(13, lw * 5), weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let inset = r.insetBy(dx: 10, dy: 8)
        (text as NSString).draw(in: inset, withAttributes: attrs)
    }

    private static func strokePath(from a: NSPoint, to b: NSPoint, width: CGFloat, dash: [CGFloat] = []) {
        let p = NSBezierPath(); p.move(to: a); p.line(to: b)
        p.lineWidth = width; p.lineCapStyle = .round
        if !dash.isEmpty { p.setLineDash(dash, count: dash.count, phase: 0) }
        p.stroke()
    }

    private static func drawHead(_ type: ArrowHead, at p: NSPoint, from other: NSPoint,
                                 width: CGFloat, sizeScale: Double, color: NSColor) {
        guard type != .none else { return }
        color.setFill(); color.setStroke()
        let angle = atan2(p.y - other.y, p.x - other.x)
        switch type {
        case .arrow:
            let len = max(12, width * 4) * sizeScale, spread = CGFloat.pi / 7
            let p1 = NSPoint(x: p.x - len * cos(angle - spread), y: p.y - len * sin(angle - spread))
            let p2 = NSPoint(x: p.x - len * cos(angle + spread), y: p.y - len * sin(angle + spread))
            let path = NSBezierPath()
            path.move(to: p); path.line(to: p1); path.line(to: p2); path.close(); path.fill()
        case .dot:
            let r = max(3, width * 1.7) * sizeScale
            NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
        case .bar:
            let len = max(6, width * 3) * sizeScale, perp = angle + .pi / 2
            let a = NSPoint(x: p.x + len * cos(perp), y: p.y + len * sin(perp))
            let b = NSPoint(x: p.x - len * cos(perp), y: p.y - len * sin(perp))
            let path = NSBezierPath(); path.move(to: a); path.line(to: b)
            path.lineWidth = width; path.lineCapStyle = .round; path.stroke()
        case .none: break
        }
    }

    private static func drawText(_ text: String, at point: NSPoint, color: NSColor, size: CGFloat) {
        let str = text.isEmpty ? "Text" : text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
        ]
        // point is the top-left of the text in top-left space → shift down by cap height.
        let h = (str as NSString).size(withAttributes: attrs).height
        (str as NSString).draw(at: NSPoint(x: point.x, y: point.y - h), withAttributes: attrs)
    }

    private static func drawStep(_ label: String, center: NSPoint, radius: CGFloat, color: NSColor) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        color.setFill(); NSBezierPath(ovalIn: rect).fill()
        NSColor.white.setStroke(); let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 2; ring.stroke()
        let s = label as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
            .foregroundColor: NSColor.white,
        ]
        let sz = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
    }

    private static func drawBlur(rectTL: CGRect, imageHeight h: Int, base: CGImage, ctx: CGContext) {
        let bl = NSRect(x: rectTL.minX, y: CGFloat(h) - rectTL.maxY, width: rectTL.width, height: rectTL.height)
        guard let region = ImageOps.crop(base, to: CGRect(x: rectTL.minX, y: rectTL.minY,
                                                          width: rectTL.width, height: rectTL.height)) else { return }
        let ci = CIImage(cgImage: region)
        let block = CGFloat(ImageOps.clampBlock(Int(min(rectTL.width, rectTL.height) / 12)))
        guard let filter = CIFilter(name: "CIPixellate") else { return }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        filter.setValue(block, forKey: kCIInputScaleKey)
        guard let out = filter.outputImage?.cropped(to: ci.extent),
              let cg = ciContext.createCGImage(out, from: ci.extent) else { return }
        ctx.draw(cg, in: bl)
    }
}
