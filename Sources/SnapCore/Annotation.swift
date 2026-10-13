import CoreGraphics

/// The annotation tools available in the editor.
public enum Tool: String, CaseIterable, Sendable, Codable {
    case arrow, line, rect, ellipse, text, callout, step, highlight, blur, pen, crop, stamp, spotlight, magnify, smartMove
}

/// Endpoint decoration for arrows/lines.
public enum ArrowHead: String, CaseIterable, Sendable, Codable {
    case none, arrow, dot, bar
    public var title: String { rawValue.capitalized }
}

/// Arrow head size.
public enum ArrowSize: String, CaseIterable, Sendable, Codable {
    case small, medium, large
    public var title: String { rawValue.capitalized }
    public var scale: Double {
        switch self { case .small: return 0.7; case .medium: return 1.0; case .large: return 1.5 }
    }
}

/// Stroke style for arrows, lines, and shape outlines.
public enum LineStyle: String, CaseIterable, Sendable, Codable {
    case solid, dashed, dotted

    /// Dash pattern for a given stroke width (empty = solid).
    public func dashPattern(width: Double) -> [Double] {
        switch self {
        case .solid: return []
        case .dashed: return [max(2, width * 3), max(2, width * 2)]
        case .dotted: return [max(0.5, width * 0.1), max(2, width * 1.8)]
        }
    }
}

/// How step badges are labelled: 1,2,3 · A,B,C · a,b,c.
public enum StepStyle: String, CaseIterable, Sendable, Codable {
    case number, upper, lower

    public func label(for n: Int) -> String {
        switch self {
        case .number: return "\(n)"
        case .upper: return StepStyle.letters(n, base: "A")
        case .lower: return StepStyle.letters(n, base: "a")
        }
    }

    /// 1→A, 26→Z, 27→AA …
    private static func letters(_ n: Int, base: Character) -> String {
        var n = max(1, n)
        var s = ""
        let start = Int(base.asciiValue!)
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(start + r)!) + s
            n = (n - 1) / 26
        }
        return s
    }
}

/// A single placed annotation. Value type — the document owns the array.
public struct Annotation: Identifiable, Equatable, Sendable, Codable {
    public let id: Int
    public var tool: Tool
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    public var colorHex: String
    public var thickness: Double
    /// Only set for `.step` badges.
    public var stepNumber: Int?
    /// Filled vs. outline for rect/ellipse.
    public var filled: Bool
    /// 0…1 opacity.
    public var opacity: Double
    /// Numbering style for `.step` badges.
    public var stepStyle: StepStyle
    /// Stroke style for arrows/lines/shape outlines.
    public var lineStyle: LineStyle
    /// Head decorations for arrows/lines.
    public var startHead: ArrowHead
    public var endHead: ArrowHead
    public var arrowSize: ArrowSize
    /// Freehand path for `.pen` strokes (start/end hold its bounding corners).
    public var points: [CGPoint]

    public init(id: Int, tool: Tool, start: CGPoint, end: CGPoint, text: String = "",
                colorHex: String = "#FF3B30", thickness: Double = 3, stepNumber: Int? = nil,
                filled: Bool = false, opacity: Double = 1, stepStyle: StepStyle = .number,
                lineStyle: LineStyle = .solid, startHead: ArrowHead = .none,
                endHead: ArrowHead = .arrow, arrowSize: ArrowSize = .medium, points: [CGPoint] = []) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.text = text
        self.colorHex = colorHex
        self.thickness = thickness
        self.stepNumber = stepNumber
        self.filled = filled
        self.opacity = opacity
        self.stepStyle = stepStyle
        self.lineStyle = lineStyle
        self.startHead = startHead
        self.endHead = endHead
        self.arrowSize = arrowSize
        self.points = points
    }

    /// Move the whole annotation, including any freehand points.
    public mutating func translate(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    public mutating func transform(_ map: (CGPoint) -> CGPoint) {
        start = map(start); end = map(end)
        points = points.map(map)
    }

    /// The rendered label for a step badge (e.g. "1", "A", "b").
    public var stepLabel: String { stepStyle.label(for: stepNumber ?? 1) }
}

/// A non-destructive stack of annotations over a captured image.
public struct AnnotationDocument: Sendable, Codable {
    public private(set) var items: [Annotation] = []
    private var nextID = 1
    private var nextStep = 1

    public init() {}

    @discardableResult
    public mutating func add(_ tool: Tool, start: CGPoint, end: CGPoint,
                             text: String = "", colorHex: String = "#FF3B30",
                             thickness: Double = 3, filled: Bool = false,
                             opacity: Double = 1, stepStyle: StepStyle = .number,
                             lineStyle: LineStyle = .solid, startHead: ArrowHead = .none,
                             endHead: ArrowHead = .arrow, arrowSize: ArrowSize = .medium) -> Annotation {
        let step = (tool == .step) ? nextStep : nil
        if tool == .step { nextStep += 1 }
        let a = Annotation(id: nextID, tool: tool, start: start, end: end,
                           text: text, colorHex: colorHex, thickness: thickness,
                           stepNumber: step, filled: filled, opacity: opacity,
                           stepStyle: stepStyle, lineStyle: lineStyle,
                           startHead: startHead, endHead: endHead, arrowSize: arrowSize)
        nextID += 1
        items.append(a)
        return a
    }

    /// Shift every annotation by a delta (used when cropping the base image).
    public mutating func translateAll(dx: CGFloat, dy: CGFloat) {
        for i in items.indices { items[i].translate(dx: dx, dy: dy) }
    }

    /// Nudge or drag a single annotation.
    public mutating func translate(id: Int, dx: CGFloat, dy: CGFloat) {
        update(id: id) { $0.translate(dx: dx, dy: dy) }
    }

    /// One freehand stroke as a single selectable object.
    @discardableResult
    public mutating func addStroke(_ points: [CGPoint], style: AnnotationStyle) -> Annotation? {
        guard points.count > 1 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let a = style.applied(to: Annotation(id: nextID, tool: .pen,
                                             start: CGPoint(x: xs.min() ?? 0, y: ys.min() ?? 0),
                                             end: CGPoint(x: xs.max() ?? 0, y: ys.max() ?? 0),
                                             points: points))
        nextID += 1
        items.append(a)
        return a
    }

    public mutating func restyle(id: Int, to style: AnnotationStyle) {
        update(id: id) { $0 = style.applied(to: $0) }
    }

    /// Apply a style to every annotation made with `tool` (Snagit's "select all of type").
    /// Returns how many changed.
    @discardableResult
    public mutating func restyleAll(of tool: Tool, to style: AnnotationStyle) -> Int {
        var changed = 0
        for index in items.indices where items[index].tool == tool {
            let restyled = style.applied(to: items[index])
            if restyled != items[index] { items[index] = restyled; changed += 1 }
        }
        return changed
    }

    /// Insert a copy of `source` (which may no longer be in the document, e.g. after a cut),
    /// shifted by `offset`. Steps take the next number in the sequence.
    @discardableResult
    public mutating func insertCopy(of source: Annotation, offset: CGPoint = CGPoint(x: 16, y: 16)) -> Annotation {
        var copy = source
        copy = Annotation(id: nextID, tool: copy.tool, start: copy.start, end: copy.end, text: copy.text,
                          colorHex: copy.colorHex, thickness: copy.thickness,
                          stepNumber: copy.tool == .step ? nextStep : copy.stepNumber,
                          filled: copy.filled, opacity: copy.opacity, stepStyle: copy.stepStyle,
                          lineStyle: copy.lineStyle, startHead: copy.startHead,
                          endHead: copy.endHead, arrowSize: copy.arrowSize, points: copy.points)
        copy.translate(dx: offset.x, dy: offset.y)
        nextID += 1
        if copy.tool == .step { nextStep += 1 }
        items.append(copy)
        return copy
    }

    public mutating func remove(id: Int) {
        items.removeAll { $0.id == id }
    }

    public mutating func update(id: Int, _ transform: (inout Annotation) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[idx])
    }

    @discardableResult
    public mutating func duplicate(id: Int, offset: CGPoint = CGPoint(x: 16, y: 16)) -> Annotation? {
        guard let source = items.first(where: { $0.id == id }) else { return nil }
        return insertCopy(of: source, offset: offset)
    }

    public mutating func bringToFront(id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.append(items.remove(at: index))
    }

    public mutating func sendToBack(id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.insert(items.remove(at: index), at: 0)
    }

    public mutating func transformAll(_ transform: (CGPoint) -> CGPoint) {
        for index in items.indices { items[index].transform(transform) }
    }

    public var stepCount: Int { items.filter { $0.tool == .step }.count }
    public var isEmpty: Bool { items.isEmpty }
}

/// The visual properties of an annotation, separate from its geometry — what the properties
/// panel edits and what gets applied when restyling a selection.
public struct AnnotationStyle: Equatable, Sendable, Codable {
    public var colorHex: String
    public var thickness: Double
    public var filled: Bool
    public var opacity: Double
    public var stepStyle: StepStyle
    public var lineStyle: LineStyle
    public var startHead: ArrowHead
    public var endHead: ArrowHead
    public var arrowSize: ArrowSize

    public init(colorHex: String = "#FF3B30", thickness: Double = 3, filled: Bool = false, opacity: Double = 1,
                stepStyle: StepStyle = .number, lineStyle: LineStyle = .solid, startHead: ArrowHead = .none,
                endHead: ArrowHead = .arrow, arrowSize: ArrowSize = .medium) {
        self.colorHex = colorHex; self.thickness = thickness; self.filled = filled; self.opacity = opacity
        self.stepStyle = stepStyle; self.lineStyle = lineStyle; self.startHead = startHead
        self.endHead = endHead; self.arrowSize = arrowSize
    }

    public init(of a: Annotation) {
        self.init(colorHex: a.colorHex, thickness: a.thickness, filled: a.filled, opacity: a.opacity,
                  stepStyle: a.stepStyle, lineStyle: a.lineStyle, startHead: a.startHead,
                  endHead: a.endHead, arrowSize: a.arrowSize)
    }

    /// `a` with this style; geometry, text and step number are kept. Opacity is clamped to 0.05…1
    /// so a restyle can never make an annotation invisible and unselectable.
    public func applied(to a: Annotation) -> Annotation {
        var out = a
        out.colorHex = colorHex; out.thickness = max(0.5, thickness); out.filled = filled
        out.opacity = min(1, max(0.05, opacity)); out.stepStyle = stepStyle; out.lineStyle = lineStyle
        out.startHead = startHead; out.endHead = endHead; out.arrowSize = arrowSize
        return out
    }
}
