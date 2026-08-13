import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic, tiff, webp
    var id: String { rawValue }
    var title: String { rawValue == "jpeg" ? "JPEG" : rawValue.uppercased() }
    var ext: String { rawValue == "jpeg" ? "jpg" : rawValue }
    var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .webp: return UTType(filenameExtension: "webp") ?? .image
        }
    }
}

/// Copy / save / drag-out for a finished (flattened) capture.
@MainActor
enum Exporter {
    static func nsImage(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func copyToPasteboard(_ cg: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage(cg)])
    }

    static func pngData(_ cg: CGImage) -> Data? {
        data(cg, format: .png)
    }

    static func data(_ cg: CGImage, format: ExportFormat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil)
        else { return nil }
        let options: CFDictionary? = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary : nil
        CGImageDestinationAddImage(dest, cg, options)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Present a save panel and write a PNG. Returns the URL if saved.
    @discardableResult
    static func savePNG(_ cg: CGImage, suggestedName: String = "Snappilot") -> URL? {
        save(cg, format: .png, suggestedName: suggestedName)
    }

    @discardableResult
    static func save(_ cg: CGImage, format: ExportFormat, suggestedName: String = "Snappilot") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = "\(suggestedName).\(format.ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let data = data(cg, format: format) else { return nil }
        try? data.write(to: url)
        return url
    }
}
