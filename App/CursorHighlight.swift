import AppKit

/// A presentation-grade cursor spotlight + click ripples, drawn on a click-through overlay
/// so it's captured into the recording without blocking interaction.
@MainActor
final class CursorHighlight {
    static let shared = CursorHighlight()

    private var windows: [NSWindow] = []
    private var views: [CursorHighlightView] = []
    private var monitor: Any?
    private var timer: Timer?

    func start() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.setFrame(screen.frame, display: true)
            win.level = .floating
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = false
            win.ignoresMouseEvents = true          // click-through — you interact normally
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = CursorHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size), screen: screen)
            win.contentView = view
            win.orderFrontRegardless()
            windows.append(win); views.append(view)
        }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged]) { [weak self] e in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            let click = (e.type == .leftMouseDown || e.type == .rightMouseDown)
            for v in self.views { v.update(global: p, click: click) }
        }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.views.forEach { $0.needsDisplay = true } }
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll(); views.removeAll()
    }
}

private final class CursorHighlightView: NSView {
    private let screenRef: NSScreen
    private var cursor: NSPoint?
    private var ripples: [(point: NSPoint, born: Date)] = []

    init(frame: NSRect, screen: NSScreen) {
        self.screenRef = screen
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(global: NSPoint, click: Bool) {
        let local = NSPoint(x: global.x - screenRef.frame.minX, y: global.y - screenRef.frame.minY)
        cursor = local
        if click, bounds.contains(local) { ripples.append((local, Date())) }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Expire old ripples.
        let now = Date()
        ripples.removeAll { now.timeIntervalSince($0.born) > 0.5 }

        if let c = cursor, bounds.contains(c) {
            // Soft spotlight ring around the pointer.
            let r: CGFloat = 26
            NSColor.systemYellow.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
            NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ring.lineWidth = 3; ring.stroke()
        }

        // Click ripples — expanding + fading rings.
        for rip in ripples {
            let age = now.timeIntervalSince(rip.born)
            let progress = age / 0.5
            let radius = 14 + CGFloat(progress) * 70
            let alpha = max(0, 1 - progress)
            NSColor.systemYellow.withAlphaComponent(CGFloat(alpha) * 0.9).setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x: rip.point.x - radius, y: rip.point.y - radius,
                                                   width: radius * 2, height: radius * 2))
            path.lineWidth = 4; path.stroke()
        }
    }
}
