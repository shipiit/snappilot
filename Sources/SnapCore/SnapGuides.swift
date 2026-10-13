import CoreGraphics

/// Smart alignment while dragging: a moving rect snaps its edges or centre to the canvas and
/// to other objects, and reports the guide lines to draw.
public enum SnapGuides {
    public enum Axis: Sendable { case vertical, horizontal }

    /// A guide line: `position` is the x (vertical) or y (horizontal) coordinate, spanning
    /// `from`…`to` along the other axis.
    public struct Guide: Equatable, Sendable {
        public let axis: Axis
        public let position: CGFloat
        public let from: CGFloat
        public let to: CGFloat
    }

    public struct Result: Equatable, Sendable {
        public let rect: CGRect
        public let guides: [Guide]
    }

    /// Snap `rect` to the canvas edges/centre and to `others`' edges/centres when within
    /// `threshold`. Each axis snaps independently to its closest candidate.
    public static func snap(_ rect: CGRect, to others: [CGRect], canvas: CGSize, threshold: CGFloat) -> Result {
        let canvasRect = CGRect(origin: .zero, size: canvas)
        let targets = [canvasRect] + others
        let xTargets = targets.flatMap { [$0.minX, $0.midX, $0.maxX] }
        let yTargets = targets.flatMap { [$0.minY, $0.midY, $0.maxY] }

        let dx = bestOffset(from: [rect.minX, rect.midX, rect.maxX], to: xTargets, threshold: threshold)
        let dy = bestOffset(from: [rect.minY, rect.midY, rect.maxY], to: yTargets, threshold: threshold)
        let snapped = rect.offsetBy(dx: dx ?? 0, dy: dy ?? 0)

        var guides: [Guide] = []
        if dx != nil {
            for x in Set([snapped.minX, snapped.midX, snapped.maxX]) {
                let matches = targets.filter { [$0.minX, $0.midX, $0.maxX].contains { abs($0 - x) < 0.5 } }
                guard !matches.isEmpty else { continue }
                let span = matches.reduce(snapped) { $0.union($1) }
                guides.append(Guide(axis: .vertical, position: x, from: span.minY, to: span.maxY))
            }
        }
        if dy != nil {
            for y in Set([snapped.minY, snapped.midY, snapped.maxY]) {
                let matches = targets.filter { [$0.minY, $0.midY, $0.maxY].contains { abs($0 - y) < 0.5 } }
                guard !matches.isEmpty else { continue }
                let span = matches.reduce(snapped) { $0.union($1) }
                guides.append(Guide(axis: .horizontal, position: y, from: span.minX, to: span.maxX))
            }
        }
        return Result(rect: snapped, guides: guides.sorted { ($0.axis == .vertical ? 0 : 1, $0.position) < ($1.axis == .vertical ? 0 : 1, $1.position) })
    }

    private static func bestOffset(from anchors: [CGFloat], to targets: [CGFloat], threshold: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for anchor in anchors {
            for target in targets {
                let delta = target - anchor
                if abs(delta) <= threshold, abs(delta) < abs(best ?? .infinity) { best = delta }
            }
        }
        return best
    }
}
