import CoreGraphics

/// Grab points on a selected annotation: the two ends of a line/arrow, or the four corners
/// of a box-shaped annotation. Badge-like annotations (text, step, stamp, pen) have none.
public enum AnnotationHandle: Equatable, Sendable {
    case start, end
    case topLeft, topRight, bottomLeft, bottomRight

    public static func handles(for a: Annotation) -> [(AnnotationHandle, CGPoint)] {
        switch a.tool {
        case .arrow, .line:
            return [(.start, a.start), (.end, a.end)]
        case .rect, .ellipse, .highlight, .blur, .spotlight, .magnify, .callout:
            let r = selectionRect(from: a.start, to: a.end)
            return [(.topLeft, CGPoint(x: r.minX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
                    (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.bottomRight, CGPoint(x: r.maxX, y: r.maxY))]
        case .text, .step, .stamp, .pen, .crop, .smartMove:
            return []
        }
    }

    /// The handle within `tolerance` of `point`, nearest first.
    public static func hit(_ point: CGPoint, on a: Annotation, tolerance: CGFloat) -> AnnotationHandle? {
        handles(for: a)
            .map { ($0.0, hypot(point.x - $0.1.x, point.y - $0.1.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    /// `original` with this handle dragged to `point`. Corners resize against the opposite
    /// corner and can be dragged past it (the box flips, as in any drawing app).
    public func dragged(_ original: Annotation, to point: CGPoint) -> Annotation {
        var out = original
        switch self {
        case .start: out.start = point
        case .end: out.end = point
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let r = selectionRect(from: original.start, to: original.end)
            let anchor: CGPoint
            switch self {
            case .topLeft: anchor = CGPoint(x: r.maxX, y: r.maxY)
            case .topRight: anchor = CGPoint(x: r.minX, y: r.maxY)
            case .bottomLeft: anchor = CGPoint(x: r.maxX, y: r.minY)
            default: anchor = CGPoint(x: r.minX, y: r.minY)
            }
            out.start = anchor
            out.end = point
        }
        return out
    }
}
