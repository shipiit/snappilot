import CoreGraphics

/// Where image overlays land on the editor canvas and how they stack. Canvas coordinates
/// are the base image's pixel space (top-left origin).
public enum LayerPlacement {
    public static let minSide: CGFloat = 24

    /// Scale an image down (never up) so it takes at most `maxFraction` of the canvas.
    public static func fittedSize(_ image: CGSize, canvas: CGSize, maxFraction: CGFloat = 0.55) -> CGSize {
        guard image.width > 0, image.height > 0 else { return CGSize(width: minSide, height: minSide) }
        let scale = min(1, canvas.width * maxFraction / image.width, canvas.height * maxFraction / image.height)
        return CGSize(width: max(minSide, image.width * scale), height: max(minSide, image.height * scale))
    }

    /// A rect of `size` centred on `center`, shifted so it stays inside the canvas whenever it fits.
    public static func rect(size: CGSize, centeredAt center: CGPoint, in canvas: CGSize) -> CGRect {
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        if size.width <= canvas.width { origin.x = min(max(0, origin.x), canvas.width - size.width) }
        if size.height <= canvas.height { origin.y = min(max(0, origin.y), canvas.height - size.height) }
        return CGRect(origin: origin, size: size)
    }

    /// Placement for a new overlay with no explicit drop point: the canvas centre, stepped
    /// diagonally past any overlay already sitting there so each new image visibly overlaps
    /// the previous one instead of hiding exactly behind it.
    public static func cascadedRect(size: CGSize, in canvas: CGSize, existing: [CGRect]) -> CGRect {
        let step = max(minSide, min(canvas.width, canvas.height) * 0.04)
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let first = rect(size: size, centeredAt: center, in: canvas)
        var previous: CGRect?
        for index in 0..<64 {
            let shift = CGFloat(index) * step
            let candidate = rect(size: size, centeredAt: CGPoint(x: center.x + shift, y: center.y + shift),
                                 in: canvas)
            if candidate == previous { break }   // pinned against the canvas corner; no room left
            previous = candidate
            let isTaken = existing.contains {
                abs($0.minX - candidate.minX) < step / 2 && abs($0.minY - candidate.minY) < step / 2
            }
            if !isTaken { return candidate }
        }
        return first
    }

    /// Move the element at `index` to the end (frontmost). Returns false when nothing changed.
    @discardableResult
    public static func bringToFront<T>(_ items: inout [T], index: Int) -> Bool {
        guard items.indices.contains(index), index != items.count - 1 else { return false }
        items.append(items.remove(at: index))
        return true
    }

    /// Canvas growth needed so every rect fits with `padding` around the overflowing sides.
    /// `offset` is how far existing content shifts (positive when growing left/up).
    public static func expansion(canvas: CGSize, fitting rects: [CGRect],
                                 padding: CGFloat = 0) -> (size: CGSize, offset: CGVector)? {
        let canvasRect = CGRect(origin: .zero, size: canvas)
        let content = rects.reduce(canvasRect) { $0.union($1) }
        guard content != canvasRect else { return nil }
        let left = content.minX < 0 ? -content.minX + padding : 0
        let top = content.minY < 0 ? -content.minY + padding : 0
        let right = content.maxX > canvas.width ? content.maxX - canvas.width + padding : 0
        let bottom = content.maxY > canvas.height ? content.maxY - canvas.height + padding : 0
        return (CGSize(width: (canvas.width + left + right).rounded(.up),
                       height: (canvas.height + top + bottom).rounded(.up)),
                CGVector(dx: left.rounded(.up), dy: top.rounded(.up)))
    }

    /// Where an image goes when combined beside the canvas: to its right, top-aligned,
    /// at full size, separated by `gap`.
    public static func besideRect(size: CGSize, canvas: CGSize, gap: CGFloat) -> CGRect {
        CGRect(x: canvas.width + gap, y: 0, width: size.width, height: size.height)
    }
}
