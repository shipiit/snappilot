import AppKit
@preconcurrency import AVFoundation

/// Captures a single full-resolution webcam still and returns it as a CGImage.
@MainActor
final class WebcamPhotoCapture: NSObject, @preconcurrency AVCapturePhotoCaptureDelegate {
    static let shared = WebcamPhotoCapture()
    private var session: AVCaptureSession?
    private var completion: ((CGImage?) -> Void)?

    func capture(completion: @escaping (CGImage?) -> Void) {
        self.completion = completion
        Task {
            guard await AppState.access(.video) == .granted,
                  let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                finish(nil); return
            }
            let session = AVCaptureSession(); session.sessionPreset = .photo
            let output = AVCapturePhotoOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else { finish(nil); return }
            session.addInput(input); session.addOutput(output)
            self.session = session
            nonisolated(unsafe) let sessionRef = session
            DispatchQueue.global(qos: .userInitiated).async {
                sessionRef.startRunning()
                DispatchQueue.main.async {
                    output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else { finish(nil); return }
        var rect = NSRect(origin: .zero, size: image.size)
        finish(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
    }

    private func finish(_ image: CGImage?) {
        if let session {
            nonisolated(unsafe) let sessionRef = session
            DispatchQueue.global(qos: .utility).async { sessionRef.stopRunning() }
        }
        session = nil
        let callback = completion; completion = nil
        callback?(image)
    }
}
