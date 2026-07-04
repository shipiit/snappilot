import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Present a save panel and write a PNG. Returns the URL if saved.
    @discardableResult
    static func savePNG(_ cg: CGImage, suggestedName: String = "Snappilot") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(suggestedName).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let data = pngData(cg) else { return nil }
        try? data.write(to: url)
        return url
    }
}
