@preconcurrency import ScreenCaptureKit
import AVFoundation
import AppKit
import SnapCore

/// Recording quality — trades file size against sharpness.
enum RecordQuality: String, CaseIterable, Codable {
    case small, balanced, high
    var title: String {
        switch self { case .small: return "Small"; case .balanced: return "Balanced"; case .high: return "High" }
    }
    var subtitle: String {
        switch self {
        case .small: return "Smallest file · 1×"
        case .balanced: return "Sharp & compact · up to 1.5×"
        case .high: return "Crispest · full Retina · 60fps"
        }
    }
    var fps: Int32 { self == .high ? 60 : 30 }
    var bitsPerPixel: Double {
        switch self { case .small: return 0.10; case .balanced: return 0.16; case .high: return 0.22 }
    }
    /// Output pixel scale applied to the region's point dimensions.
    func pixelScale(screenScale: CGFloat) -> CGFloat {
        switch self {
        case .small: return 1.0
        case .balanced: return min(screenScale, 1.5)
        case .high: return screenScale
        }
    }
}

/// Records a screen region/display to an MP4 (HEVC + audio) using ScreenCaptureKit and
/// AVAssetWriter. Video frames arrive on a background queue and are appended to the
/// writer on a dedicated serial queue.
final class RecordingController: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = RecordingController()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "ai.snappilot.recording")
    private var started = false
    private var finishing = false
    private(set) var isRecording = false
    private var outputURL: URL?
    private var pixelSize = CGSize.zero
    private var videoFPS: Int32 = 30
    private var videoBitrate = 6_000_000
    var recordingPixelSize: CGSize { pixelSize }

    /// Called on the main thread when recording stops, with the finished file (or nil).
    var onFinish: ((URL?) -> Void)?

    /// Start recording. `rectInScreen` is bottom-left screen-local points; nil = full display.
    @MainActor
    func start(rectInScreen: CGRect?, on screen: NSScreen,
               systemAudio: Bool, micAudio: Bool, captureCursor: Bool = true,
               quality: RecordQuality = .balanced) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = CaptureController.screenNumber(screen)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else { throw CaptureError.noDisplay }
        let scale = screen.backingScaleFactor

        // Microphone capture needs macOS 15+.
        var micEnabled = false
        if micAudio, #available(macOS 15.0, *) { micEnabled = true }

        let pixelScale = quality.pixelScale(screenScale: scale)
        videoFPS = quality.fps

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: videoFPS)
        config.queueDepth = 6
        config.showsCursor = captureCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = systemAudio
        if micEnabled, #available(macOS 15.0, *) { config.captureMicrophone = true }

        if let rect = rectInScreen {
            // SCStream sourceRect is top-left points relative to the display.
            let topLeftY = screen.frame.height - rect.maxY
            config.sourceRect = CGRect(x: rect.minX, y: topLeftY, width: rect.width, height: rect.height)
            config.width = Int(rect.width * pixelScale)
            config.height = Int(rect.height * pixelScale)
        } else {
            config.width = Int(CGFloat(display.width) * pixelScale)
            config.height = Int(CGFloat(display.height) * pixelScale)
        }
        pixelSize = CGSize(width: config.width, height: config.height)

        // Bitrate scales with resolution & fps; clamped to a sane range.
        let area = Double(config.width * config.height)
        videoBitrate = max(2_500_000, min(40_000_000, Int(area * Double(videoFPS) * quality.bitsPerPixel)))

        try setupWriter(systemAudio: systemAudio, micAudio: micEnabled)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if micEnabled, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        self.stream = stream
        try await stream.startCapture()
        isRecording = true
    }

    private func setupWriter(systemAudio: Bool, micAudio: Bool) throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("snappilot-\(UUID().uuidString.prefix(6)).mp4")
        outputURL = url
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Compress efficiently: HEVC + a bitrate targeted at ~0.07 bits/pixel/frame @30fps,
        // clamped to a sane range. A 20s region recording lands around a few MB.
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoMaxKeyFrameIntervalKey: Int(videoFPS) * 2,
                AVVideoExpectedSourceFrameRateKey: videoFPS,
            ],
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vInput) { writer.add(vInput) }
        videoInput = vInput

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000,
        ]
        if systemAudio {
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) { writer.add(aInput) }
            audioInput = aInput
        }
        if micAudio {
            let mInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            mInput.expectsMediaDataInRealTime = true
            if writer.canAdd(mInput) { writer.add(mInput) }
            micInput = mInput
        }
        self.writer = writer
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, !self.finishing else { return }
            self.finishing = true
            self.isRecording = false
            let stream = self.stream
            // Stop the stream first, then finalize the writer on our serial queue so it
            // never races with an in-flight sample append (which would crash).
            if let stream {
                stream.stopCapture { [weak self] _ in
                    self?.queue.async { self?.finishRecording() }
                }
            } else {
                self.finishRecording()
            }
        }
    }

    /// Runs on `queue`. Finish the writer safely and report the file (or nil).
    private func finishRecording() {
        guard let writer else { report(nil); reset(); return }
        guard started, writer.status == .writing else {
            // Never got a frame — nothing valid to write.
            writer.cancelWriting()
            report(nil); reset(); return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            let url = writer.status == .completed ? self.outputURL : nil
            self.report(url)
            self.queue.async { self.reset() }
        }
    }

    private func report(_ url: URL?) {
        let finished = onFinish
        DispatchQueue.main.async { finished?(url) }
    }

    private func reset() {
        stream = nil; writer = nil; videoInput = nil; audioInput = nil; micInput = nil
        started = false; finishing = false; outputURL = nil
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !finishing, CMSampleBufferDataIsReady(sampleBuffer), let writer else { return }

        if type == .screen {
            // Skip frames flagged as incomplete/blank.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw), status == .complete else { return }

            if !started {
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                started = true
            }
            if let input = videoInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        } else if type == .audio, started, let input = audioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else if #available(macOS 15.0, *), type == .microphone, started,
                  let input = micInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { Toast.show("Recording stopped: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill") }
    }
}
