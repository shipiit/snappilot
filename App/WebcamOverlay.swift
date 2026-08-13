import AppKit
import AVFoundation
import CoreImage
import Vision

enum WebcamBackgroundEffect: String, CaseIterable, Identifiable {
    case none = "None"
    case blur = "Blur Background"
    case studio = "Studio Background"
    var id: String { rawValue }
}

/// A floating webcam bubble recorded by ScreenCaptureKit. Background effects are
/// generated locally with Apple's person-segmentation model.
@MainActor
final class WebcamOverlay {
    static let shared = WebcamOverlay()

    private var window: NSWindow?
    private var session: AVCaptureSession?
    private var processor: WebcamFrameProcessor?

    var isActive: Bool { window != nil }

    func show(in area: NSRect, effect: WebcamBackgroundEffect = .none) {
        guard window == nil else { return }
        guard AVCaptureDevice.default(for: .video) != nil else {
            Toast.show("No camera found", symbol: "video.slash"); return
        }

        let diameter: CGFloat = min(200, area.width * 0.22, area.height * 0.3)
        let margin: CGFloat = 24
        let frame = NSRect(x: area.maxX - diameter - margin, y: area.minY + margin,
                           width: diameter, height: diameter)
        let win = NSWindow(contentRect: frame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level = .floating; win.isOpaque = false; win.backgroundColor = .clear
        win.hasShadow = true; win.ignoresMouseEvents = false; win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true; container.layer?.cornerRadius = diameter / 2
        container.layer?.masksToBounds = true; container.layer?.borderColor = NSColor.white.cgColor
        container.layer?.borderWidth = 3; container.layer?.contentsGravity = .resizeAspectFill

        let session = AVCaptureSession(); session.sessionPreset = .high
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }

        if effect == .none {
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = container.bounds; preview.videoGravity = .resizeAspectFill
            container.layer?.addSublayer(preview)
        } else {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_32BGRA]
            let processor = WebcamFrameProcessor(effect: effect) { [weak container] frame in
                container?.layer?.contents = frame
            }
            output.setSampleBufferDelegate(processor, queue: processor.queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            if let connection = output.connection(with: .video) { connection.isVideoMirrored = true }
            self.processor = processor
        }

        win.contentView = container; win.orderFrontRegardless()
        nonisolated(unsafe) let sessionRef = session
        DispatchQueue.global(qos: .userInitiated).async { sessionRef.startRunning() }
        self.session = session; self.window = win
    }

    func hide() {
        session?.stopRunning(); session = nil; processor = nil
        window?.orderOut(nil); window = nil
    }
}

private final class WebcamFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                                           @unchecked Sendable {
    let queue = DispatchQueue(label: "snappilot.webcam.effects", qos: .userInitiated)
    private let effect: WebcamBackgroundEffect
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let request = VNGeneratePersonSegmentationRequest()
    private let deliver: @MainActor (CGImage) -> Void
    private var frameNumber = 0

    init(effect: WebcamBackgroundEffect, deliver: @escaping @MainActor (CGImage) -> Void) {
        self.effect = effect; self.deliver = deliver
        super.init()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameNumber += 1
        guard frameNumber % 2 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let maskBuffer = request.results?.first?.pixelBuffer else { return }
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(
            scaleX: source.extent.width / mask.extent.width,
            y: source.extent.height / mask.extent.height))

        let background: CIImage
        if effect == .studio {
            background = CIImage(color: CIColor(red: 0.08, green: 0.10, blue: 0.16))
                .cropped(to: source.extent)
        } else {
            background = source.clampedToExtent().applyingFilter(
                "CIGaussianBlur", parameters: [kCIInputRadiusKey: 22]).cropped(to: source.extent)
        }
        let composite = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ]).cropped(to: source.extent)
        guard let image = context.createCGImage(composite, from: source.extent) else { return }
        Task { @MainActor in deliver(image) }
    }
}
