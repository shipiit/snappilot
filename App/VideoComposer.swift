@preconcurrency import AVFoundation
import Foundation

/// Small, local video composition utilities used by the recording preview.
enum VideoComposer {
    static func combine(_ urls: [URL], to destination: URL) async -> Bool {
        guard urls.count >= 2 else { return false }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid) else { return false }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var preferredTransform = CGAffineTransform.identity

        do {
            for (index, url) in urls.enumerated() {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: duration)
                guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
                try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
                if index == 0 { preferredTransform = try await sourceVideo.load(.preferredTransform) }
                if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                    try audioTrack?.insertTimeRange(range, of: sourceAudio, at: cursor)
                }
                cursor = CMTimeAdd(cursor, duration)
            }
            guard cursor > .zero else { return false }
            videoTrack.preferredTransform = preferredTransform
            try? FileManager.default.removeItem(at: destination)
            guard let export = AVAssetExportSession(asset: composition,
                                                    presetName: AVAssetExportPresetHighestQuality) else { return false }
            export.outputURL = destination
            export.outputFileType = .mp4
            export.shouldOptimizeForNetworkUse = true
            await export.export()
            return export.status == .completed
        } catch {
            return false
        }
    }
}
