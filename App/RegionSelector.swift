import AppKit
@preconcurrency import ScreenCaptureKit
import SnapCore

/// What the overlay produced.
enum SelectorResult {
    /// Screen + rect in that screen's local points (bottom-left origin).
    case region(NSScreen, CGRect)
    /// A window the user clicked (its CGWindowID + global top-left frame).
    case window(CGWindowID, CGRect)
    case cancelled
}

enum SelectorMode { case region, window }

/// Full-screen dim overlay with crosshair guides, a live magnifier loupe, an instruction
/// tooltip and a shortcut hints panel — a clean, modern capture experience.
@MainActor
final class RegionSelector {
    private var windows: [OverlayWindow] = []
    private var completion: ((SelectorResult) -> Void)?
    private var keyMonitor: Any?
    private static var current: RegionSelector?

    func present(mode: SelectorMode, completion: @escaping (SelectorResult) -> Void) {
        self.completion = completion
        RegionSelector.current = self

        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, mode: mode, selector: self)
            windows.append(w)
            w.makeKeyAndOrderFront(nil)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }

        // Grab per-display screenshots (for the magnifier) without our overlay in them.
        Task {
            let shots = await RegionSelector.captureScreens()
            for w in windows {
                if let view = w.contentView as? OverlayView {
                    view.screenshot = shots[view.displayID]
                    view.needsDisplay = true
                }
            }
        }
    }

    /// Returns true if the key was handled (swallowed).
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: finish(.cancelled); return true                     // Esc
        case 3:                                                       // F — full screen
            let p = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
            if let screen {
                finish(.region(screen, CGRect(origin: .zero, size: screen.frame.size)))
            }
            return true
        case 46:                                                     // M — toggle magnifier
            windows.forEach { ($0.contentView as? OverlayView)?.magnifierEnabled.toggle() }
            windows.forEach { $0.contentView?.needsDisplay = true }
            return true
        default: return false
        }
    }

    func finish(_ result: SelectorResult) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let done = completion
        completion = nil
        RegionSelector.current = nil
        done?(result)
    }

    /// Capture each display to a CGImage (top-left origin, full resolution).
    static func captureScreens() async -> [CGDirectDisplayID: CGImage] {
        var out: [CGDirectDisplayID: CGImage] = [:]
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return out }
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = CaptureController.scale(for: display.displayID)
            cfg.width = Int(CGFloat(display.width) * scale)
            cfg.height = Int(CGFloat(display.height) * scale)
            cfg.showsCursor = false
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                out[display.displayID] = img
            }
        }
        return out
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen, mode: SelectorMode, selector: RegionSelector) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                  screen: screen, mode: mode, selector: selector)
    }
    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    private let screenRef: NSScreen
    private let mode: SelectorMode
    private weak var selector: RegionSelector?

    let displayID: CGDirectDisplayID
    var screenshot: CGImage?
    var magnifierEnabled = true

    private var start: NSPoint?
    private var current: NSPoint?
    private var hoverPoint: NSPoint?
    private var hoverWindowFrame: NSRect?
    private var hoverWindowID: CGWindowID?

    private var scale: CGFloat { screenRef.backingScaleFactor }

    init(frame: NSRect, screen: NSScreen, mode: SelectorMode, selector: RegionSelector) {
        self.screenRef = screen
        self.mode = mode
        self.selector = selector
        self.displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        let accent = NSColor.systemYellow

        if mode == .region {
            if let s = start, let c = current {
                let rect = selectionRect(from: CGPoint(x: s.x, y: s.y), to: CGPoint(x: c.x, y: c.y))
                let r = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                NSColor.clear.setFill(); r.fill(using: .copy)
                accent.setStroke()
                let path = NSBezierPath(rect: r); path.lineWidth = 1.5; path.stroke()
                drawSizeLabel(for: r, pixels: true)
                drawCrosshair(at: c, color: accent.withAlphaComponent(0.5))
                drawMagnifier(at: c, selectionPixels: CGSize(width: rect.width * scale, height: rect.height * scale))
            } else if let p = hoverPoint {
                drawCrosshair(at: p, color: accent.withAlphaComponent(0.6))
                drawInstruction(near: p)
                drawMagnifier(at: p, selectionPixels: nil)
            }
        } else if mode == .window, let f = hoverWindowFrame {
            NSColor.clear.setFill(); f.fill(using: .copy)
            accent.setStroke()
            let path = NSBezierPath(rect: f); path.lineWidth = 3; path.stroke()
            drawSizeLabel(for: f, pixels: true)
        }

        drawHintsPanel()
    }

    private func drawCrosshair(at p: NSPoint, color: NSColor) {
        color.setStroke()
        let v = NSBezierPath(); v.move(to: NSPoint(x: p.x, y: 0)); v.line(to: NSPoint(x: p.x, y: bounds.height))
        let h = NSBezierPath(); h.move(to: NSPoint(x: 0, y: p.y)); h.line(to: NSPoint(x: bounds.width, y: p.y))
        v.lineWidth = 1; h.lineWidth = 1; v.stroke(); h.stroke()
    }

    private func drawInstruction(near p: NSPoint) {
        let text = "Click, hold, and drag to select region"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 8
        var x = p.x + 20, y = p.y + 20
        x = min(x, bounds.width - size.width - pad * 2 - 8)
        y = min(y, bounds.height - size.height - pad * 2 - 8)
        let box = NSRect(x: x, y: y, width: size.width + pad * 2, height: size.height + pad)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad / 2), withAttributes: attrs)
    }

    private func drawMagnifier(at p: NSPoint, selectionPixels: CGSize?) {
        guard magnifierEnabled, let shot = screenshot else { return }
        let diameter: CGFloat = 116
        let zoomPoints: CGFloat = 16      // points sampled → magnified
        var origin = NSPoint(x: p.x + 18, y: p.y - 18 - diameter)
        origin.x = max(8, min(origin.x, bounds.width - diameter - 8))
        origin.y = max(28, min(origin.y, bounds.height - diameter - 8))
        let loupe = NSRect(x: origin.x, y: origin.y, width: diameter, height: diameter)

        // Crop the cached screenshot around the cursor (top-left origin pixels).
        let side = zoomPoints * scale
        let px = p.x * scale
        let pyTop = (bounds.height - p.y) * scale
        let cropRect = CGRect(x: px - side / 2, y: pyTop - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(ovalIn: loupe); clip.addClip()
        NSColor.black.setFill(); loupe.fill()
        if cropRect.width >= 1, let crop = shot.cropping(to: cropRect.integral) {
            let img = NSImage(cgImage: crop, size: loupe.size)
            NSGraphicsContext.current?.imageInterpolation = .none
            img.draw(in: loupe)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Loupe crosshair + border
        NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
        let cx = NSBezierPath(); cx.move(to: NSPoint(x: loupe.midX, y: loupe.minY)); cx.line(to: NSPoint(x: loupe.midX, y: loupe.maxY))
        let cy = NSBezierPath(); cy.move(to: NSPoint(x: loupe.minX, y: loupe.midY)); cy.line(to: NSPoint(x: loupe.maxX, y: loupe.midY))
        cx.lineWidth = 1; cy.lineWidth = 1; cx.stroke(); cy.stroke()
        let border = NSBezierPath(ovalIn: loupe); border.lineWidth = 2; NSColor.white.withAlphaComponent(0.85).setStroke(); border.stroke()

        // Dimensions label under the loupe
        let dims = selectionPixels.map { "\(Int($0.width)) × \(Int($0.height))" }
            ?? "\(Int(bounds.width * scale)) × \(Int(bounds.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let ds = (dims as NSString).size(withAttributes: attrs)
        let lbl = NSRect(x: loupe.midX - ds.width / 2 - 6, y: loupe.minY - ds.height - 8, width: ds.width + 12, height: ds.height + 4)
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: lbl, xRadius: 4, yRadius: 4).fill()
        (dims as NSString).draw(at: NSPoint(x: lbl.minX + 6, y: lbl.minY + 2), withAttributes: attrs)
    }

    private func drawHintsPanel() {
        let lines: [(String, String)] = [
            ("Esc", "cancel capture"),
            ("F", "capture full screen"),
            ("M", "toggle magnifier"),
            ("Drag", "select a region"),
        ]
        let keyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let txtFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let rowH: CGFloat = 20, pad: CGFloat = 14
        let width: CGFloat = 210
        let height = CGFloat(lines.count) * rowH + pad * 2
        let box = NSRect(x: 24, y: 24, width: width, height: height)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).stroke()

        for (i, line) in lines.enumerated() {
            let y = box.maxY - pad - CGFloat(i + 1) * rowH + 3
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: NSColor.systemYellow]
            (line.0 as NSString).draw(at: NSPoint(x: box.minX + pad, y: y), withAttributes: keyAttrs)
            let txtAttrs: [NSAttributedString.Key: Any] = [.font: txtFont, .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
            (line.1 as NSString).draw(at: NSPoint(x: box.minX + pad + 54, y: y), withAttributes: txtAttrs)
        }
    }

    private func drawSizeLabel(for r: NSRect, pixels: Bool) {
        let w = pixels ? Int(r.width * scale) : Int(r.width)
        let h = pixels ? Int(r.height * scale) : Int(r.height)
        let text = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        var lx = r.midX - size.width / 2 - pad
        var ly = r.minY - size.height - pad * 2 - 4
        if ly < 4 { ly = r.maxY + 4 }
        lx = max(4, min(lx, bounds.width - size.width - pad * 2 - 4))
        let boxr = NSRect(x: lx, y: ly, width: size.width + pad * 2, height: size.height + pad)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: boxr, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: boxr.minX + pad, y: boxr.minY + pad / 2), withAttributes: attrs)
    }

    // MARK: Mouse
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if mode == .region {
            hoverPoint = p
        } else {
            let global = NSEvent.mouseLocation
            if let (id, frame) = WindowHitTest.window(at: global, excluding: window?.windowNumber) {
                hoverWindowID = id
                hoverWindowFrame = globalTopLeftToViewFrame(frame)
            } else { hoverWindowID = nil; hoverWindowFrame = nil }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard mode == .region else { return }
        start = convert(event.locationInWindow, from: nil); current = start; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard mode == .region else { return }
        current = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if mode == .region, let s = start, let c = current {
            let rect = selectionRect(from: CGPoint(x: s.x, y: s.y), to: CGPoint(x: c.x, y: c.y))
            if rect.width >= 4 && rect.height >= 4 { selector?.finish(.region(screenRef, rect)) }
            else { selector?.finish(.cancelled) }
        } else if mode == .window {
            if let id = hoverWindowID, let f = hoverWindowFrame {
                selector?.finish(.window(id, viewFrameToGlobalTopLeft(f)))
            } else { selector?.finish(.cancelled) }
        }
        start = nil; current = nil
    }

    // MARK: Coordinate helpers
    private func globalTopLeftToViewFrame(_ f: CGRect) -> NSRect {
        let sf = screenRef.frame
        let globalBLy = totalScreenTop() - f.maxY
        return NSRect(x: f.minX - sf.minX, y: globalBLy - sf.minY, width: f.width, height: f.height)
    }
    private func viewFrameToGlobalTopLeft(_ f: NSRect) -> CGRect {
        let sf = screenRef.frame
        let globalBLy = f.minY + sf.minY
        let globalTLy = totalScreenTop() - (globalBLy + f.height)
        return CGRect(x: f.minX + sf.minX, y: globalTLy, width: f.width, height: f.height)
    }
    private func totalScreenTop() -> CGFloat { NSScreen.screens.first?.frame.maxY ?? screenRef.frame.maxY }
}
