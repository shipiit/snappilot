import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import AppKit

/// Turns a recorded video into an animated GIF (sampled frames, scaled down, looping).
enum GIFExporter {
    /// Export `videoURL` to a GIF at `dest`. Returns true on success.
    static func export(from videoURL: URL, to dest: URL,
                       fps: Double = 12, maxWidth: CGFloat = 640) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        guard let durationSeconds = try? await asset.load(.duration).seconds,
              durationSeconds > 0 else { return false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)

        let frameCount = max(1, Int(durationSeconds * fps))
        let delay = 1.0 / fps

        guard let destination = CGImageDestinationCreateWithURL(
            dest as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { return false }

        let gifProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,   // loop forever
            ],
        ]
        CGImageDestinationSetProperties(destination, gifProps as CFDictionary)

        let frameProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: delay,
            ],
        ]

        var added = 0
        for i in 0..<frameCount {
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let cg = try? await generator.image(at: t).image {
                CGImageDestinationAddImage(destination, cg, frameProps as CFDictionary)
                added += 1
            }
        }
        guard added > 0 else { return false }
        return CGImageDestinationFinalize(destination)
    }
}
