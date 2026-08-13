import AppKit
import CoreGraphics

/// Provider-neutral sharing through the macOS sharing system. This supports AirDrop,
/// Messages, Mail and installed storage extensions without uploading automatically.
@MainActor
enum SystemShare {
    private static var activePicker: NSSharingServicePicker?

    static func image(_ image: CGImage) {
        present([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
    }

    static func file(_ url: URL) { present([url]) }

    private static func present(_ items: [Any]) {
        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            Toast.show("No window available for sharing", symbol: "square.and.arrow.up"); return
        }
        let picker = NSSharingServicePicker(items: items)
        activePicker = picker
        let anchor = NSRect(x: view.bounds.maxX - 60, y: view.bounds.maxY - 10, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}
