import Vision
import CoreGraphics

/// On-device text recognition via the Vision framework. Nothing leaves the Mac.
public enum OCR {
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
