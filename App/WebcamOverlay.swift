import AppKit
import AVFoundation

/// A floating, always-on-top circular webcam preview. Because it sits on screen inside
/// the recorded area, ScreenCaptureKit records it straight into the video — giving a
/// webcam overlay without complex frame compositing.
@MainActor
final class WebcamOverlay {
    static let shared = WebcamOverlay()

    private var window: NSWindow?
    private var session: AVCaptureSession?

    var isActive: Bool { window != nil }

    /// Show the webcam bubble near the bottom-right of `area` (global bottom-left rect).
    func show(in area: NSRect) {
        guard window == nil else { return }
        guard AVCaptureDevice.default(for: .video) != nil else {
            Toast.show("No camera found", symbol: "video.slash"); return
        }

        let diameter: CGFloat = min(200, area.width * 0.22, area.height * 0.3)
        let margin: CGFloat = 24
        let frame = NSRect(x: area.maxX - diameter - margin,
                           y: area.minY + margin,
                           width: diameter, height: diameter)

        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = false
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = diameter / 2
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.cgColor
        container.layer?.borderWidth = 3

        let session = AVCaptureSession()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = container.bounds
        preview.videoGravity = .resizeAspectFill
        container.layer?.addSublayer(preview)

        win.contentView = container
        win.orderFrontRegardless()
        nonisolated(unsafe) let sessionRef = session
        DispatchQueue.global(qos: .userInitiated).async { sessionRef.startRunning() }

        self.session = session
        self.window = win
    }

    func hide() {
        session?.stopRunning()
        session = nil
        window?.orderOut(nil)
        window = nil
    }
}
