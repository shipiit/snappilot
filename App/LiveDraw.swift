import AppKit
import SwiftUI

enum LiveTool: String, CaseIterable { case pen, highlighter, laser, arrow }

/// One freehand/arrow stroke drawn live on screen.
private struct LiveStroke {
    var tool: LiveTool
    var color: NSColor
    var width: CGFloat
    var points: [NSPoint]
    var born: Date
}

/// Drives a Google-Meet-style live drawing overlay you can use *while recording* — pen,
/// highlighter, fading laser pointer, and arrows are drawn on screen and captured into
/// the video. A small floating toolbar picks the tool/color.
@MainActor
final class LiveDrawController: ObservableObject {
    static let shared = LiveDrawController()

    @Published var tool: LiveTool = .pen { didSet { broadcast() } }
    @Published var colorHex: String = "#FF3B30" { didSet { broadcast() } }
    @Published private(set) var active = false

    private var overlays: [DrawOverlayView] = []
    private var overlayWindows: [NSWindow] = []
    private var toolbar: NSWindow?
    private var keyMonitor: Any?

    var color: NSColor { nsColor(fromHex: colorHex) }

    func toggle() { active ? stop() : start() }

    func start() {
        guard !active else { return }
        active = true
        for screen in NSScreen.screens {
            let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.setFrame(screen.frame, display: true)
            win.level = .floating          // above content (captured), below the toolbar/HUD
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = DrawOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: self)
            win.contentView = view
            win.orderFrontRegardless()
            overlayWindows.append(win)
            overlays.append(view)
        }
        showToolbar()
        broadcast()
        // Esc exits drawing (in case the toolbar is off-screen on a multi-display setup).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.stop(); return nil }
            return e
        }
    }

    func stop() {
        active = false
        overlays.forEach { $0.teardown() }
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll(); overlays.removeAll()
        toolbar?.orderOut(nil); toolbar = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func clear() { overlays.forEach { $0.clear() } }

    private func broadcast() { overlays.forEach { $0.tool = tool; $0.color = color } }

    private func showToolbar() {
        guard let screen = NSScreen.main else { return }
        let w: CGFloat = 470, h: CGFloat = 60
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - 130, width: w, height: h)
        // A non-activating panel so its buttons work WITHOUT stealing focus from the app
        // you're recording — a plain borderless window can't become key, so SwiftUI
        // buttons (like the ✕ exit) wouldn't respond, trapping you in draw mode.
        let win = KeyablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        win.isFloatingPanel = true
        win.becomesKeyOnlyIfNeeded = true
        win.level = .statusBar
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView = NSHostingView(rootView: LiveDrawToolbar(controller: self))
        win.orderFrontRegardless()
        toolbar = win
    }
}

/// A floating panel whose controls can be clicked without activating/stealing focus.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Floating tool picker for live drawing.
struct LiveDrawToolbar: View {
    @ObservedObject var controller: LiveDrawController
    private let tools: [(LiveTool, String)] = [
        (.pen, "pencil.tip"), (.highlighter, "highlighter"),
        (.laser, "cursorarrow.rays"), (.arrow, "arrow.up.right"),
    ]
    private let colors = ["#FF3B30", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tools, id: \.0) { t, icon in
                Button { controller.tool = t } label: {
                    Image(systemName: icon).frame(width: 30, height: 30)
                        .background(controller.tool == t ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(controller.tool == t ? .white : .primary)
                }.buttonStyle(.plain)
            }
            Divider().frame(height: 24)
            ForEach(colors, id: \.self) { hex in
                Circle().fill(Color(nsColor: nsColor(fromHex: hex)))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.primary.opacity(controller.colorHex == hex ? 0.9 : 0.2),
                                             lineWidth: controller.colorHex == hex ? 2 : 1))
                    .onTapGesture { controller.colorHex = hex }
            }
            Divider().frame(height: 24)
            Button { controller.clear() } label: { Image(systemName: "trash").frame(width: 28, height: 28) }
                .buttonStyle(.plain).help("Clear")
            Button { controller.stop() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(.plain).help("Stop drawing")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15)))
        .preferredColorScheme(.dark)
    }
}

/// The transparent per-screen canvas that captures the mouse and draws strokes.
private final class DrawOverlayView: NSView {
    private weak var controller: LiveDrawController?
    var tool: LiveTool = .pen
    var color: NSColor = .systemRed

    private var strokes: [LiveStroke] = []
    private var current: LiveStroke?
    private var timer: Timer?

    init(frame: NSRect, controller: LiveDrawController) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        // Fade timer for the laser pointer.
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    required init?(coder: NSCoder) { fatalError() }

    func teardown() { timer?.invalidate(); timer = nil }

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func clear() { strokes.removeAll(); current = nil; needsDisplay = true }

    private func tick() {
        // Drop expired laser strokes; keep redrawing while any are fading.
        let now = Date()
        let before = strokes.count
        strokes.removeAll { $0.tool == .laser && now.timeIntervalSince($0.born) > 1.2 }
        if strokes.contains(where: { $0.tool == .laser }) || strokes.count != before { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        current = LiveStroke(tool: tool, color: color, width: strokeWidth(tool), points: [p], born: Date())
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current?.points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if var c = current {
            c.born = Date()
            if c.tool == .arrow, c.points.count > 1 { c.points = [c.points.first!, c.points.last!] }
            strokes.append(c)
        }
        current = nil
        needsDisplay = true
    }

    private func strokeWidth(_ t: LiveTool) -> CGFloat {
        switch t { case .pen: return 4; case .highlighter: return 18; case .laser: return 6; case .arrow: return 5 }
    }

    override func draw(_ dirtyRect: NSRect) {
        for s in strokes { drawStroke(s) }
        if let c = current { drawStroke(c) }
    }

    private func drawStroke(_ s: LiveStroke) {
        guard s.points.count > 0 else { return }
        var alpha: CGFloat = 1
        if s.tool == .laser {
            let age = Date().timeIntervalSince(s.born)
            alpha = age < 0.6 ? 1 : max(0, 1 - (age - 0.6) / 0.6)
        }
        let col = s.color.withAlphaComponent(s.tool == .highlighter ? 0.35 * alpha : alpha)

        if s.tool == .arrow, s.points.count >= 2 {
            let a = s.points.first!, b = s.points.last!
            col.setStroke(); col.setFill()
            let path = NSBezierPath(); path.move(to: a); path.line(to: b)
            path.lineWidth = s.width; path.lineCapStyle = .round; path.stroke()
            let ang = cg_atan2(b.y - a.y, b.x - a.x), len = max(14, s.width * 3.2), spread = CGFloat.pi / 7
            let head = NSBezierPath(); head.move(to: b)
            head.line(to: NSPoint(x: b.x - len * cg_cos(ang - spread), y: b.y - len * cg_sin(ang - spread)))
            head.line(to: NSPoint(x: b.x - len * cg_cos(ang + spread), y: b.y - len * cg_sin(ang + spread)))
            head.close(); head.fill()
            return
        }

        let path = NSBezierPath()
        path.move(to: s.points[0])
        for p in s.points.dropFirst() { path.line(to: p) }
        path.lineWidth = s.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        col.setStroke(); path.stroke()

        if s.tool == .laser, let tip = s.points.last {
            let r: CGFloat = 9 * alpha + 3
            col.setFill(); NSBezierPath(ovalIn: NSRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)).fill()
        }
    }
}
