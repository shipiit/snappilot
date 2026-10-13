/// The user's own Quick Styles, kept per tool. Newest first, no duplicates, capped so the
/// panel stays scannable.
public struct SavedStyles: Codable, Equatable, Sendable {
    public static let limitPerTool = 12
    private var byTool: [String: [AnnotationStyle]] = [:]

    public init() {}

    public func styles(for tool: Tool) -> [AnnotationStyle] { byTool[tool.rawValue] ?? [] }

    /// Save a style for a tool. Saving an existing style moves it to the front.
    public mutating func add(_ style: AnnotationStyle, for tool: Tool) {
        var list = styles(for: tool).filter { $0 != style }
        list.insert(style, at: 0)
        byTool[tool.rawValue] = Array(list.prefix(Self.limitPerTool))
    }

    public mutating func remove(_ style: AnnotationStyle, for tool: Tool) {
        byTool[tool.rawValue] = styles(for: tool).filter { $0 != style }
    }
}
