import CoreGraphics
import CoreImage
import Vision
import SnapCore

enum LocalVisionEdits {
    private static let context = CIContext()

    /// Uses Apple's on-device foreground instance segmentation and returns transparency
    /// everywhere outside the detected foreground objects.
    static func removeBackground(_ image: CGImage) async throws -> CGImage? {
        try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let pixelBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler)
            let source = CIImage(cgImage: image)
            let mask = CIImage(cvPixelBuffer: pixelBuffer)
            guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
            filter.setValue(source, forKey: kCIInputImageKey)
            filter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            filter.setValue(mask, forKey: kCIInputMaskImageKey)
            guard let output = filter.outputImage?.cropped(to: source.extent) else { return nil }
            return context.createCGImage(output, from: source.extent)
        }.value
    }

    /// Keeps the detected foreground sharp while applying a Gaussian blur behind it.
    static func blurBackground(_ image: CGImage, radius: Double = 18) async throws -> CGImage? {
        try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let pixelBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler)
            let source = CIImage(cgImage: image)
            let mask = CIImage(cvPixelBuffer: pixelBuffer)
            guard let blur = CIFilter(name: "CIGaussianBlur"),
                  let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
            blur.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(radius, forKey: kCIInputRadiusKey)
            blend.setValue(source, forKey: kCIInputImageKey)
            blend.setValue(blur.outputImage?.cropped(to: source.extent), forKey: kCIInputBackgroundImageKey)
            blend.setValue(mask, forKey: kCIInputMaskImageKey)
            guard let output = blend.outputImage?.cropped(to: source.extent) else { return nil }
            return context.createCGImage(output, from: source.extent)
        }.value
    }

    /// A fast local "simplify" treatment: reduce color complexity and visual noise while
    /// preserving hard UI edges and readable structure.
    static func simplify(_ image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        guard let noise = CIFilter(name: "CINoiseReduction"),
              let posterize = CIFilter(name: "CIColorPosterize") else { return nil }
        noise.setValue(source, forKey: kCIInputImageKey)
        noise.setValue(0.04, forKey: "inputNoiseLevel")
        noise.setValue(0.55, forKey: "inputSharpness")
        posterize.setValue(noise.outputImage, forKey: kCIInputImageKey)
        posterize.setValue(10, forKey: "inputLevels")
        guard let output = posterize.outputImage?.cropped(to: source.extent) else { return nil }
        return context.createCGImage(output, from: source.extent)
    }

    /// Finds the most likely visual UI element at a clicked pixel. Rectangle detection
    /// handles cards, buttons and windows; OCR boxes make labels and controls selectable.
    static func smartMoveRect(in image: CGImage, at point: CGPoint,
                              languages: [String]) async throws -> CGRect? {
        async let textBoxes = OCR.recognizeBoxes(image, languages: languages)
        async let rectangles: [CGRect] = Task.detached(priority: .userInitiated) {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 80
            request.minimumConfidence = 0.45
            request.minimumAspectRatio = 0.08
            request.minimumSize = 0.015
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let width = CGFloat(image.width), height = CGFloat(image.height)
            return (request.results ?? []).map { observation in
                let box = observation.boundingBox
                return CGRect(x: box.minX * width, y: (1 - box.maxY) * height,
                              width: box.width * width, height: box.height * height).integral
            }
        }.value

        let textRects = try await textBoxes.map {
            $0.rect.insetBy(dx: -max(8, $0.rect.height * 0.45),
                            dy: -max(5, $0.rect.height * 0.3)).integral
        }
        let candidates = try await rectangles + textRects
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let valid = candidates.map { $0.intersection(bounds) }.filter { $0.width >= 12 && $0.height >= 12 }
        if let containing = valid.filter({ $0.insetBy(dx: -5, dy: -5).contains(point) })
            .min(by: { $0.width * $0.height < $1.width * $1.height }) {
            return containing
        }
        return valid.min { distance(point, to: $0) < distance(point, to: $1) }
            .flatMap { distance(point, to: $0) <= max(40, min(bounds.width, bounds.height) * 0.05) ? $0 : nil }
    }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
