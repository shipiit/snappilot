import AVFoundation

/// Captures the microphone through the system voice-processing audio unit, which applies
/// real-time **noise suppression + echo cancellation + automatic gain** — the same engine
/// behind macOS "Voice Isolation". Emits `CMSampleBuffer`s stamped on the host-time clock
/// so they line up with ScreenCaptureKit's video frames on the recording timeline.
///
/// This is used instead of ScreenCaptureKit's raw `.microphone` output when the user turns
/// on noise cancellation, and it works on macOS 13+ (SCStream mic needs 15+).
final class VoiceMic: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var onSample: ((CMSampleBuffer) -> Void)?
    private var formatDesc: CMAudioFormatDescription?
    private(set) var running = false

    /// Start capturing. `onSample` is called on the audio engine's render thread — the
    /// caller is responsible for hopping to whatever queue owns the asset writer.
    func start(onSample: @escaping (CMSampleBuffer) -> Void) throws {
        self.onSample = onSample
        let input = engine.inputNode
        // Enabling voice processing on the input node turns on NS/AEC/AGC. It must be set
        // before the engine is prepared/started.
        try input.setVoiceProcessingEnabled(true)

        let format = input.outputFormat(forBus: 0)
        var asbd = format.streamDescription.pointee
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                       layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &formatDesc)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            self?.emit(buffer, at: when)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        onSample = nil
    }

    private func emit(_ pcm: AVAudioPCMBuffer, at when: AVAudioTime) {
        guard let onSample, let fd = formatDesc, pcm.frameLength > 0 else { return }
        // AVAudioTime.hostTime and SCStream video PTS share the host-time clock.
        let pts = CMClockMakeHostTimeFromSystemUnits(when.hostTime)
        guard let sb = Self.sampleBuffer(from: pcm, format: fd, pts: pts) else { return }
        onSample(sb)
    }

    /// Wrap a PCM buffer in a CMSampleBuffer the asset writer can consume.
    private static func sampleBuffer(from pcm: AVAudioPCMBuffer,
                                     format fd: CMAudioFormatDescription,
                                     pts: CMTime) -> CMSampleBuffer? {
        let sampleRate = pcm.format.sampleRate
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid)

        var sb: CMSampleBuffer?
        var status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: fd,
            sampleCount: CMItemCount(pcm.frameLength), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sb)
        guard status == noErr, let sb else { return nil }

        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sb, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
            bufferList: pcm.mutableAudioBufferList)
        guard status == noErr else { return nil }
        return sb
    }
}
