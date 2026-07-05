import AppKit

/// Floats a capture on top of everything as an always-visible reference ("Pin to Screen").
@MainActor
enum PinBoard {
    private static var pins: [(window: NSWindow, delegate: PinDelegate)] = []

    static func pin(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        pin(image: image)
    }

    static func pin(image: NSImage) {
        let maxEdge: CGFloat = 460
        var w = max(1, image.size.width), h = max(1, image.size.height)
        let scale = min(1, maxEdge / max(w, h))
        w *= scale; h *= scale

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Pinned"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.hasShadow = true
        win.center()

        let iv = NSImageView()
        iv.image = image
        iv.imageScaling = .scaleAxesIndependently
        win.contentView = iv
        win.orderFrontRegardless()

        let delegate = PinDelegate { pins.removeAll { $0.window == win } }
        win.delegate = delegate
        pins.append((win, delegate))
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class PinDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
