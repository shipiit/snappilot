import AppKit

/// A click-through border drawn just *outside* the recording region so the user always
/// sees exactly what's being recorded — without the border appearing in the video.
@MainActor
final class RecordingFrame {
    static let shared = RecordingFrame()

    private var window: NSWindow?
    private var timer: Timer?
    private static var phase: CGFloat = 0
    private static weak var frameView: FrameView?

    /// `globalRect` is the recorded area in global bottom-left coordinates.
    func show(globalRect: NSRect) {
        hide()
        let margin: CGFloat = 5
        let winFrame = globalRect.insetBy(dx: -margin, dy: -margin)

        let win = NSWindow(contentRect: winFrame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = FrameView(frame: NSRect(origin: .zero, size: winFrame.size))
        win.contentView = view
        win.orderFrontRegardless()
        window = win
        RecordingFrame.frameView = view

        // Animated "marching ants".
        let t = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { RecordingFrame.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func tick() {
        phase -= 1
        frameView?.dashPhase = phase
        frameView?.needsDisplay = true
    }

    func hide() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil
        RecordingFrame.frameView = nil
    }
}

private final class FrameView: NSView {
    var dashPhase: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        // Border sits at the window edge = a few px *outside* the recorded region.
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        path.lineWidth = 3
        NSColor.systemYellow.setStroke()
        path.setLineDash([8, 5], count: 2, phase: dashPhase)
        path.stroke()
    }
}
