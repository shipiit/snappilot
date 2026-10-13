import AVFoundation

/// Recordings write system audio and the microphone as separate tracks, but most players and
/// uploaders only play the first audio track — so narration silently disappears. This folds
/// every audio track into one, keeping the video stream untouched (no re-encode).
public enum AudioMixdown {
    public enum Failure: Error { case exportFailed(stage: String, underlying: String) }

    public static func audioTrackCount(of url: URL) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).count
    }

    /// Rewrite `url` in place with a single mixed audio track. Returns false (and leaves the
    /// file alone) when there is nothing to mix.
    @discardableResult
    public static func mixInPlace(_ url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count >= 2 else { return false }
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snappilot-mix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. Audio-only composition → M4A export sums the tracks into one.
        let audioOnly = AVMutableComposition()
        for track in audioTracks {
            let target = audioOnly.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try await insert(track, into: target, clampedTo: range)
        }
        let mixedAudioURL = workDir.appendingPathComponent("mixed.m4a")
        try await export(audioOnly, preset: AVAssetExportPresetAppleM4A, to: mixedAudioURL, type: .m4a, stage: "mix audio")

        // 2. Original video + the mixed track, passed through without re-encoding.
        // Keep the asset alive: a track doesn't retain its asset, and a freed asset fails with -12780.
        let mixedAsset = AVURLAsset(url: mixedAudioURL)
        let mixedTrack = try await mixedAsset.loadTracks(withMediaType: .audio).first
        let final = AVMutableComposition()
        for videoTrack in try await asset.loadTracks(withMediaType: .video) {
            let target = final.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try await insert(videoTrack, into: target, clampedTo: range)
            target?.preferredTransform = try await videoTrack.load(.preferredTransform)
        }
        if let mixedTrack {
            let target = final.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try await insert(mixedTrack, into: target, clampedTo: range)
        }
        let outputURL = workDir.appendingPathComponent("final.mp4")
        try await export(final, preset: AVAssetExportPresetPassthrough, to: outputURL, type: .mp4, stage: "remux video")
        _ = try FileManager.default.replaceItemAt(url, withItemAt: outputURL)
        withExtendedLifetime(mixedAsset) {}
        return true
    }

    /// A track's media can end before the asset does; inserting past its end throws (-12780).
    private static func insert(_ track: AVAssetTrack, into target: AVMutableCompositionTrack?,
                               clampedTo range: CMTimeRange) async throws {
        let available = try await track.load(.timeRange).intersection(range)
        guard let target, available.duration > .zero else { return }
        try target.insertTimeRange(available, of: track, at: available.start)
    }

    private static func export(_ asset: AVAsset, preset: String, to url: URL, type: AVFileType,
                               stage: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.exportFailed(stage: stage, underlying: "no export session for \(preset)")
        }
        if #available(macOS 15.0, *) {
            do { try await session.export(to: url, as: type) } catch {
                throw Failure.exportFailed(stage: stage, underlying: "\(error)")
            }
        } else {
            session.outputURL = url
            session.outputFileType = type
            await session.export()
            if session.status != .completed {
                throw Failure.exportFailed(stage: stage,
                                           underlying: session.error.map { "\($0)" } ?? "status \(session.status.rawValue)")
            }
        }
    }
}
