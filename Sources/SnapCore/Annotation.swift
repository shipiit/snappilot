import CoreGraphics

/// The annotation tools available in the editor.
public enum Tool: String, CaseIterable, Sendable {
    case arrow, line, rect, ellipse, text, callout, step, highlight, blur, pen, crop, stamp
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
public struct Annotation: Identifiable, Equatable, Sendable {
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

    public init(id: Int, tool: Tool, start: CGPoint, end: CGPoint, text: String = "",
                colorHex: String = "#FF3B30", thickness: Double = 3, stepNumber: Int? = nil,
                filled: Bool = false, opacity: Double = 1, stepStyle: StepStyle = .number,
                lineStyle: LineStyle = .solid, startHead: ArrowHead = .none,
                endHead: ArrowHead = .arrow, arrowSize: ArrowSize = .medium) {
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
    }

    /// The rendered label for a step badge (e.g. "1", "A", "b").
    public var stepLabel: String { stepStyle.label(for: stepNumber ?? 1) }
}

/// A non-destructive stack of annotations over a captured image.
public struct AnnotationDocument: Sendable {
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
        for i in items.indices {
            items[i].start.x += dx; items[i].start.y += dy
            items[i].end.x += dx; items[i].end.y += dy
        }
    }

    public mutating func remove(id: Int) {
        items.removeAll { $0.id == id }
    }

    public mutating func update(id: Int, _ transform: (inout Annotation) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[idx])
    }

    public var stepCount: Int { items.filter { $0.tool == .step }.count }
    public var isEmpty: Bool { items.isEmpty }
}
