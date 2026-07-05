import Foundation
import AVFoundation
import Speech
import SnapCore

enum MeetingTranscribeError: LocalizedError {
    case notAuthorized, noAudio, recognizerUnavailable, onDeviceUnavailable
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech Recognition permission is off. Enable it in System Settings › Privacy & Security › Speech Recognition."
        case .noAudio: return "This recording has no audio to transcribe."
        case .recognizerUnavailable: return "Speech recognition isn't available for your language."
        case .onDeviceUnavailable: return "On-device speech recognition isn't installed for your language yet. Add the language in System Settings › Keyboard › Dictation."
        }
    }
}

/// Transcribes a screen recording on-device into speaker-labelled lines.
///
/// A meeting recording carries two audio tracks — the mic (that's *You*) and system audio
/// (that's *everyone else in the call*). We transcribe each track independently, so speaker
/// separation comes for free without any voice-fingerprinting. Recognition runs locally
/// (`requiresOnDeviceRecognition`), in overlapping-free time windows so long meetings don't
/// hit the recognizer's per-request limits.
enum MeetingTranscriber {
    /// Ask for Speech Recognition permission.
    static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Transcribe `url`. `hasParticipants`/`hasYou` describe which audio tracks were recorded
    /// (system audio → Participants, mic → You), matching the order they were written.
    static func transcribe(url: URL, hasParticipants: Bool, hasYou: Bool,
                           progress: @Sendable @escaping (String) -> Void) async throws -> [TranscriptLine] {
        guard await authorize() else { throw MeetingTranscribeError.notAuthorized }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw MeetingTranscribeError.noAudio }

        // Map tracks to speaker labels. At record time system audio is written before the mic.
        var jobs: [(track: AVAssetTrack, label: String)] = []
        if hasParticipants && hasYou && audioTracks.count >= 2 {
            jobs = [(audioTracks[0], "Participants"), (audioTracks[1], "You")]
        } else if hasYou && !hasParticipants {
            jobs = [(audioTracks[0], "You")]
        } else if hasParticipants && !hasYou {
            jobs = [(audioTracks[0], "Participants")]
        } else {
            jobs = [(audioTracks[0], audioTracks.count >= 2 ? "Participants" : "Meeting")]
            if audioTracks.count >= 2 { jobs.append((audioTracks[1], "You")) }
        }

        let total = try await asset.load(.duration).seconds
        var lines: [TranscriptLine] = []
        let window = 120.0            // transcribe in 2-minute windows

        for job in jobs {
            var offset = 0.0
            while offset < total {
                let len = min(window, total - offset)
                progress("Transcribing \(job.label) — \(Int(offset))s of \(Int(total))s…")
                let clipURL = try await exportClip(track: job.track, of: asset,
                                                   start: offset, duration: len)
                defer { try? FileManager.default.removeItem(at: clipURL) }
                if let segs = try? await recognize(clipURL) {
                    lines.append(contentsOf: utterances(from: segs, speaker: job.label, offset: offset))
                }
                offset += len
            }
        }
        return lines.sorted { $0.start < $1.start }
    }

    /// Export one audio track's time window to a temporary .m4a.
    private static func exportClip(track: AVAssetTrack, of asset: AVAsset,
                                   start: Double, duration: Double) async throws -> URL {
        let comp = AVMutableComposition()
        guard let compTrack = comp.addMutableTrack(withMediaType: .audio,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MeetingTranscribeError.noAudio
        }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: duration, preferredTimescale: 600))
        try compTrack.insertTimeRange(range, of: track, at: .zero)

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-mtg-\(UUID().uuidString.prefix(6)).m4a")
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
            throw MeetingTranscribeError.noAudio
        }
        export.outputURL = out
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else {
            throw export.error ?? MeetingTranscribeError.noAudio
        }
        return out
    }

    /// Run on-device recognition over a clip; returns (word, timestamp-within-clip) segments.
    private static func recognize(_ url: URL) async throws -> [(text: String, t: TimeInterval)] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            throw MeetingTranscribeError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw MeetingTranscribeError.onDeviceUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !resumed { resumed = true; cont.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal, !resumed else { return }
                resumed = true
                let segs = result.bestTranscription.segments.map { ($0.substring, $0.timestamp) }
                cont.resume(returning: segs)
            }
        }
    }

    /// Group recognized words into natural turns, breaking on gaps of silence.
    private static func utterances(from segs: [(text: String, t: TimeInterval)],
                                   speaker: String, offset: Double) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var current = ""
        var start = 0.0
        var last = -100.0
        for seg in segs {
            let word = seg.text.trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            if current.isEmpty {
                start = seg.t
            } else if seg.t - last > 1.4 {                 // silence → new turn
                lines.append(TranscriptLine(speaker: speaker,
                                            text: current.trimmingCharacters(in: .whitespaces),
                                            start: offset + start))
                current = ""; start = seg.t
            }
            current += (current.isEmpty ? "" : " ") + word
            last = seg.t
        }
        if !current.isEmpty {
            lines.append(TranscriptLine(speaker: speaker,
                                        text: current.trimmingCharacters(in: .whitespaces),
                                        start: offset + start))
        }
        return lines
    }
}
