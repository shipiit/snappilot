import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The editable state behind a capture, saved next to its flattened PNG so "Annotate Again"
/// reopens live annotations and image layers instead of a flat picture.
///
/// Layout: `<capture>.snappilot/project.json`, `base.png` (the unannotated image) and one
/// `layer-<id>.png` per image layer.
public struct EditorProject: Codable, Equatable, Sendable {
    public struct Layer: Codable, Equatable, Sendable {
        public var id: Int
        public var rect: CGRect
        public var opacity: Double
        public var name: String
        public init(id: Int, rect: CGRect, opacity: Double, name: String) {
            self.id = id; self.rect = rect; self.opacity = opacity; self.name = name
        }
        var fileName: String { "layer-\(id).png" }
    }

    public static let currentVersion = 1
    public var version: Int
    public var doc: AnnotationDocument
    public var layers: [Layer]
    public var framed: Bool
    /// Rounded-corner radius in pixels; nil in projects saved before the option existed.
    public var cornerRadius: Double?

    public init(doc: AnnotationDocument, layers: [Layer], framed: Bool, cornerRadius: Double? = nil) {
        self.version = Self.currentVersion
        self.doc = doc; self.layers = layers; self.framed = framed; self.cornerRadius = cornerRadius
    }

    public static func == (lhs: EditorProject, rhs: EditorProject) -> Bool {
        lhs.version == rhs.version && lhs.doc.items == rhs.doc.items && lhs.layers == rhs.layers
            && lhs.framed == rhs.framed && lhs.cornerRadius == rhs.cornerRadius
    }

    /// The project folder that belongs to a capture file.
    public static func folder(for captureURL: URL) -> URL {
        captureURL.deletingPathExtension().appendingPathExtension("snappilot")
    }

    public enum Failure: Error, Equatable { case unreadable(String), unsupportedVersion(Int), imageWrite(String) }

    public struct Loaded: @unchecked Sendable {
        public let project: EditorProject
        public let base: CGImage
        public let layerImages: [Int: CGImage]
    }

    /// Write the project. Replaces any previous version atomically (a half-written project
    /// never replaces a good one).
    public static func save(_ project: EditorProject, base: CGImage, layerImages: [Int: CGImage],
                            to folder: URL) throws {
        let fm = FileManager.default
        let staging = folder.deletingLastPathComponent()
            .appendingPathComponent(".\(folder.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try writePNG(base, to: staging.appendingPathComponent("base.png"))
            for layer in project.layers {
                guard let image = layerImages[layer.id] else { continue }
                try writePNG(image, to: staging.appendingPathComponent(layer.fileName))
            }
            try JSONEncoder().encode(project).write(to: staging.appendingPathComponent("project.json"))
            if fm.fileExists(atPath: folder.path) {
                _ = try fm.replaceItemAt(folder, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: folder)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Read a project, or nil when the capture has none.
    public static func load(from folder: URL) throws -> Loaded? {
        let jsonURL = folder.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return nil }
        let project = try JSONDecoder().decode(EditorProject.self, from: Data(contentsOf: jsonURL))
        guard project.version <= currentVersion else { throw Failure.unsupportedVersion(project.version) }
        guard let base = readPNG(folder.appendingPathComponent("base.png")) else {
            throw Failure.unreadable("base.png")
        }
        var images: [Int: CGImage] = [:]
        for layer in project.layers {
            guard let image = readPNG(folder.appendingPathComponent(layer.fileName)) else {
                throw Failure.unreadable(layer.fileName)
            }
            images[layer.id] = image
        }
        return Loaded(project: project, base: base, layerImages: images)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.imageWrite(url.lastPathComponent) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.imageWrite(url.lastPathComponent) }
    }

    private static func readPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
