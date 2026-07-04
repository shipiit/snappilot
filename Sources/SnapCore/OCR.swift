import Vision
import CoreGraphics

/// A recognized text line and its rect in the image's pixel space (top-left origin).
public struct TextBox: Sendable {
    public let text: String
    public let rect: CGRect
    public init(text: String, rect: CGRect) { self.text = text; self.rect = rect }
}

/// On-device text recognition via the Vision framework. Nothing leaves the Mac.
public enum OCR {

    /// Recognize text with per-line bounding boxes (pixel space, top-left origin).
    public static func recognizeBoxes(_ image: CGImage,
                                      languages: [String] = ["en-US"]) async throws -> [TextBox] {
        try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let w = CGFloat(image.width), h = CGFloat(image.height)
                let boxes: [TextBox] = obs.compactMap { o in
                    guard let s = o.topCandidates(1).first?.string else { return nil }
                    let bb = o.boundingBox   // normalized, bottom-left origin
                    let rect = CGRect(x: bb.minX * w, y: (1 - bb.maxY) * h,
                                      width: bb.width * w, height: bb.height * h)
                    return TextBox(text: s, rect: rect)
                }
                cont.resume(returning: boxes)
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = languages
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([req]) }
            catch { cont.resume(throwing: error) }
        }
    }
    /// Recognize text in an image, returned as lines ordered top-to-bottom.
    public static func recognize(_ image: CGImage,
                                 languages: [String] = ["en-US"]) async throws -> [String] {
        try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = obs
                    .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = languages
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
