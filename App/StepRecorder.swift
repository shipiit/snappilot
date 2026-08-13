import AppKit
import CoreGraphics
import SnapCore

@MainActor
final class StepRecorder {
    static let shared = StepRecorder()
    private var monitor: Any?
    private var steps: [CGImage] = []
    private var capturing = false
    private var completion: ((CGImage?) -> Void)?
    private var window: NSWindow?
    private var countLabel: NSTextField?

    var isRunning: Bool { monitor != nil }

    func start(completion: @escaping (CGImage?) -> Void) {
        guard monitor == nil else { return }
        self.completion = completion; steps.removeAll()
        showHUD()
        // Read the global pointer position when another app receives a click.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.recordClick(at: point) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; window?.orderOut(nil); window = nil
        let output = StepGuideComposer.compose(steps)
        let callback = completion; completion = nil; steps.removeAll()
        callback?(output)
    }

    private func recordClick(at point: CGPoint) {
        guard !capturing, steps.count < 30 else { return }
        capturing = true
        Task {
            defer { capturing = false }
            try? await Task.sleep(for: .milliseconds(180))
            guard let result = try? await CaptureController.captureFullScreenExcludingApp(at: point),
                  let screen = CaptureController.screen(for: result.selection.displayID) else { return }
            let local = CGPoint(x: (point.x - screen.frame.minX) * result.selection.scale,
                                y: (screen.frame.maxY - point.y) * result.selection.scale)
            let marked = StepGuideComposer.mark(result.image, at: local, number: steps.count + 1)
            steps.append(marked)
            countLabel?.stringValue = "\(steps.count) step\(steps.count == 1 ? "" : "s")"
        }
    }

    private func showHUD() {
        let size = NSSize(width: 250, height: 48)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.maxY - 72,
                           width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar; window.isOpaque = false; window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]; window.hasShadow = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 18
        let dot = NSView(frame: NSRect(x: 16, y: 19, width: 10, height: 10)); dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor; dot.layer?.cornerRadius = 5
        background.addSubview(dot)
        let label = NSTextField(labelWithString: "0 steps"); label.frame = NSRect(x: 36, y: 14, width: 90, height: 22)
        label.font = .systemFont(ofSize: 13, weight: .semibold); background.addSubview(label); countLabel = label
        let stop = NSButton(title: "Finish Guide", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded; stop.frame = NSRect(x: 132, y: 9, width: 104, height: 30); background.addSubview(stop)
        window.contentView = background; window.orderFrontRegardless(); self.window = window
    }

    @objc private func stopTapped() { stop() }
}

enum StepGuideComposer {
    static func mark(_ image: CGImage, at point: CGPoint, number: Int) -> CGImage {
        let copy = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        copy.lockFocus()
        let center = NSPoint(x: point.x, y: CGFloat(image.height) - point.y)
        let radius: CGFloat = 24
        NSColor.systemRed.setFill(); NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                                 width: radius * 2, height: radius * 2)).fill()
        NSColor.white.setStroke(); let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                                          width: radius * 2, height: radius * 2))
        ring.lineWidth = 3; ring.stroke()
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
        copy.unlockFocus()
        var rect = NSRect(origin: .zero, size: copy.size)
        return copy.cgImage(forProposedRect: &rect, context: nil, hints: nil) ?? image
    }

    static func compose(_ images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let width = min(1400, images.map(\.width).max() ?? 1400)
        let margin = 48, gap = 36, heading = 72
        let sizes = images.map { image -> CGSize in
            let scale = min(1, CGFloat(width - margin * 2) / CGFloat(image.width))
            return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        }
        let height = heading + margin + sizes.reduce(0) { $0 + Int($1.height) } + gap * max(0, images.count - 1) + margin
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: false,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        let title = "Step-by-step guide" as NSString
        title.draw(at: NSPoint(x: margin, y: height - 54), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.labelColor])
        var y = CGFloat(height - heading - margin)
        for (index, image) in images.enumerated() {
            let size = sizes[index]; y -= size.height
            let rect = NSRect(x: (CGFloat(width) - size.width) / 2, y: y, width: size.width, height: size.height)
            NSImage(cgImage: image, size: size).draw(in: rect)
            y -= CGFloat(gap)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
