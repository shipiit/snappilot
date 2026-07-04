import AVFoundation
import QuartzCore
import CoreGraphics
import AppKit

/// Extracts a frame from a recording to annotate, then bakes the annotation overlay onto
/// the whole clip and re-encodes it.
enum VideoAnnotator {
    /// A representative frame (middle of the clip) to draw on.
    static func grabFrame(from url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        let t = CMTime(seconds: max(0, dur / 2), preferredTimescale: 600)
        return try? await gen.image(at: t).image
    }

    /// Composite `overlay` (transparent PNG at the frame's size) over the video for its full
    /// duration and export to `dest`.
    static func bake(overlay: CGImage, over videoURL: URL, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        guard let comp = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset) else {
            return false
        }
        let renderSize = comp.renderSize
        guard renderSize.width > 0, renderSize.height > 0 else { return false }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contents = overlay
        overlayLayer.contentsGravity = .resize

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.addSublayer(videoLayer)
        parent.addSublayer(overlayLayer)

        comp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parent)

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return false
        }
        try? FileManager.default.removeItem(at: dest)
        export.outputURL = dest
        export.outputFileType = .mp4
        export.videoComposition = comp
        nonisolated(unsafe) let e = export
        return await withCheckedContinuation { cont in
            e.exportAsynchronously { cont.resume(returning: e.status == .completed) }
        }
    }
}
