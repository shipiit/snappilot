import CoreGraphics

/// The annotation tools available in the editor.
public enum Tool: String, CaseIterable, Sendable {
    case arrow, line, rect, ellipse, text, step, highlight, blur, pen, crop
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

    public init(id: Int, tool: Tool, start: CGPoint, end: CGPoint, text: String = "",
                colorHex: String = "#FF3B30", thickness: Double = 3, stepNumber: Int? = nil) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.text = text
        self.colorHex = colorHex
        self.thickness = thickness
        self.stepNumber = stepNumber
    }
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
                             thickness: Double = 3) -> Annotation {
        let step = (tool == .step) ? nextStep : nil
        if tool == .step { nextStep += 1 }
        let a = Annotation(id: nextID, tool: tool, start: start, end: end,
                           text: text, colorHex: colorHex, thickness: thickness, stepNumber: step)
        nextID += 1
        items.append(a)
        return a
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
