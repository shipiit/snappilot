import SnapCore
import CoreGraphics
import Foundation
import AppKit
import ImageIO
import AVFoundation

var failures = 0
@MainActor func check(_ cond: Bool, _ msg: String) {
    if cond { print("ok   - \(msg)") } else { failures += 1; print("FAIL - \(msg)") }
}

// MARK: Geometry
let r = selectionRect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 20, y: 10))
check(r == CGRect(x: 20, y: 10, width: 80, height: 70), "selectionRect normalizes reversed drag")

let sel = CaptureSelection(rect: CGRect(x: 0, y: 0, width: 100, height: 50), displayID: 1, scale: 2.0)
check(sel.pixelSize == CGSize(width: 200, height: 100), "pixelSize = points x scale")

// Region crop math: bottom-left points → top-left pixels.
// rect (20,30,100,50) on a 900pt-tall retina (2x) screen: maxY=80 → topY=820 → ×2.
let crop = pixelCropRect(selection: CGRect(x: 20, y: 30, width: 100, height: 50),
                         screenHeightPoints: 900, scale: 2)
check(crop == CGRect(x: 40, y: 1640, width: 200, height: 100),
      "pixelCropRect flips Y and scales (got \(crop))")
// A selection at the very top of the screen maps to y=0 in pixels.
let topCrop = pixelCropRect(selection: CGRect(x: 0, y: 850, width: 100, height: 50),
                            screenHeightPoints: 900, scale: 2)
check(topCrop.minY == 0, "selection at screen top crops from pixel y=0 (got \(topCrop.minY))")
check(sel.isValid, "non-empty selection is valid")
check(!CaptureSelection(rect: .zero, displayID: 1, scale: 2).isValid, "zero selection invalid")

// MARK: ImageOps
func renderSolid(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
check(ImageOps.clampBlock(0) == 2, "block size floored to 2")
check(ImageOps.clampBlock(999) == 64, "block size capped at 64")
check(ImageOps.clampBlock(12) == 12, "block size in range unchanged")
check(ImageOps.fit(CGSize(width: 4000, height: 2000), maxEdge: 1000) == CGSize(width: 1000, height: 500),
      "fit scales longest edge to max")
check(ImageOps.fit(CGSize(width: 300, height: 200), maxEdge: 1000) == CGSize(width: 300, height: 200),
      "fit leaves already-small size")
if let fixture = renderSolid(width: 12, height: 8) {
    check(ImageOps.resized(fixture, width: 6, height: 4)?.width == 6, "resize changes pixel dimensions")
    let rotated = ImageOps.rotatedRight(fixture)
    check(rotated?.width == 8 && rotated?.height == 12, "rotate swaps width and height")
    check(ImageOps.flippedHorizontal(fixture)?.width == 12, "horizontal flip preserves dimensions")
    let filled = ImageOps.filling(fixture, rect: CGRect(x: 2, y: 2, width: 4, height: 3))
    check(filled?.width == 12 && filled?.height == 8, "smart-move fill preserves canvas dimensions")
}

// MARK: Redaction
check(Redaction.containsEmail("ping rahul@iamrraj.com now"), "detects email")
check(!Redaction.containsEmail("no address here"), "no false email")
check(Redaction.containsCardNumber("4242 4242 4242 4242"), "detects Luhn-valid card")
check(!Redaction.containsCardNumber("1234 5678 9012 3456"), "rejects non-Luhn digits")

// MARK: Annotation
var doc = AnnotationDocument()
let s1 = doc.add(.step, start: .zero, end: .zero)
let s2 = doc.add(.step, start: .zero, end: .zero)
check(s1.stepNumber == 1 && s2.stepNumber == 2, "step badges auto-increment")
let a1 = doc.add(.arrow, start: .zero, end: CGPoint(x: 10, y: 10))
check(a1.stepNumber == nil, "non-step has no step number")
check(Tool.allCases.contains(.smartMove), "smart move is available as an editor tool")
doc.remove(id: s1.id)
check(doc.stepCount == 1, "removal is non-destructive to others")
doc.update(id: s2.id) { $0.colorHex = "#00FF00" }
check(doc.items.first(where: { $0.id == s2.id })?.colorHex == "#00FF00", "update mutates in place")
let duplicate = doc.duplicate(id: a1.id)
check(duplicate != nil && duplicate!.id != a1.id, "duplicate creates a new annotation")
if let duplicate { doc.sendToBack(id: duplicate.id); check(doc.items.first?.id == duplicate.id, "send to back changes layer order") }

// Step numbering styles
check(StepStyle.number.label(for: 3) == "3", "numeric step label")
check(StepStyle.upper.label(for: 1) == "A", "upper letter A")
check(StepStyle.upper.label(for: 26) == "Z", "upper letter Z")
check(StepStyle.upper.label(for: 27) == "AA", "upper letter wraps to AA")
check(StepStyle.lower.label(for: 2) == "b", "lower letter b")

// MARK: OCR (renders text, recognizes it; skips gracefully if Vision unavailable)
func renderText(_ s: String) -> CGImage? {
    let size = NSSize(width: 320, height: 120)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 56),
        .foregroundColor: NSColor.black,
    ]
    (s as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: attrs)
    image.unlockFocus()
    var rect = NSRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

// MARK: Library
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let fixedDate = cal.date(from: DateComponents(year: 2026, month: 7, day: 4,
                                              hour: 14, minute: 30, second: 5))!
check(CaptureLibrary.relativeFolder(for: fixedDate, calendar: cal) == "2026/07",
      "library groups by YYYY/MM")
let stem = CaptureLibrary.stem(for: fixedDate, suffix: "a1b2", calendar: cal)
check(stem.hasPrefix("2026-07-04_") && stem.hasSuffix("_a1b2"), "stem is sortable timestamp (got \(stem))")
let path = CaptureLibrary.relativePath(for: fixedDate, suffix: "a1b2", ext: "png", calendar: cal)
check(path.hasPrefix("2026/07/") && path.hasSuffix(".png"), "relativePath = folder/stem.ext (got \(path))")
let rec = CaptureRecord(id: "x", kind: .image, fileName: path, createdAt: fixedDate,
                        width: 100, height: 50, ocrText: "Invoice total 42.00", title: "Receipt")
check(CaptureLibrary.matches(rec, query: "invoice"), "search finds OCR text")
check(CaptureLibrary.matches(rec, query: "receipt"), "search finds title")
check(!CaptureLibrary.matches(rec, query: "banana"), "search rejects absent term")
check(CaptureLibrary.matches(rec, query: ""), "empty query matches all")

if let img = renderText("HELLO") {
    do {
        let lines = try await OCR.recognize(img)
        let joined = lines.joined(separator: " ").uppercased()
        check(joined.contains("HELLO"), "OCR reads rendered text (got: \(lines))")
    } catch {
        print("skip - OCR unavailable in this environment: \(error)")
    }
} else {
    print("skip - could not render OCR fixture")
}

// MARK: Meeting analysis
let meetingLines = [
    TranscriptLine(speaker: "You", text: "Thanks everyone for joining. Let's ship the release on Friday.", start: 1),
    TranscriptLine(speaker: "Participants", text: "Sounds good. I'll handle the QA testing before then.", start: 5),
    TranscriptLine(speaker: "Participants", text: "We agreed the deadline is Friday at 5pm.", start: 9),
    TranscriptLine(speaker: "You", text: "Can you also write the release notes?", start: 13),
    TranscriptLine(speaker: "Participants", text: "Yeah.", start: 16),   // fragment, should be dropped
]
let notes = MeetingAnalyzer.analyze(meetingLines)
check(notes.tasks.contains { $0.text.lowercased().contains("qa testing") },
      "extracts 'I'll handle QA' as a task")
check(notes.tasks.contains { $0.owner == "Participants" && $0.text.lowercased().contains("qa") },
      "owner of 'I'll handle QA' is the speaker (Participants)")
check(notes.tasks.contains { $0.text.lowercased().contains("release notes") && $0.owner == "Participants" },
      "'can you write release notes' delegates to Participants")
check(notes.keyPoints.contains { $0.lowercased().contains("deadline is friday") },
      "extracts the deadline as a key point")
check(!notes.summary.isEmpty, "summary is non-empty")
check(!notes.tasks.contains { $0.text.lowercased() == "yeah." },
      "one-word fragments are not tasks")
check(MeetingAnalyzer.splitSentences("One. Two! Three?").count == 3, "splits three sentences")

// MARK: Scrolling capture stitcher
func grad(_ w: Int, _ h: Int) -> CGImage? {   // monotonic, distinct rows, no modular wrap
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    for row in 0..<h {
        ctx.setFillColor(gray: CGFloat(row) / CGFloat(max(1, h - 1)), alpha: 1)
        ctx.fill(CGRect(x: 0, y: h - 1 - row, width: w, height: 1))   // row 0 = top
    }
    return ctx.makeImage()
}
if let source = grad(40, 250) {
    // Simulate scrolling: 150-tall viewport moving down 50px at a time.
    let offsets = [0, 50, 100]
    let frames = offsets.compactMap { source.cropping(to: CGRect(x: 0, y: $0, width: 40, height: 150)) }
    check(frames.count == 3, "built 3 scroll frames")
    if let stitched = ScrollStitcher.stitch(frames) {
        check(stitched.width == 40, "stitched keeps width")
        check(abs(stitched.height - 250) <= 10, "stitched recovers full height (got \(stitched.height))")
    } else {
        check(false, "stitch produced an image")
    }
    // Two identical frames → no new rows appended (overlap ≈ full height).
    if let f = frames.first {
        let same = ScrollStitcher.stitch([f, f])
        check(same != nil && abs(same!.height - f.height) <= 6, "identical frames don't duplicate")
    }
}

// MARK: Kanban task board
var task = TaskItem(title: "Ship release", status: .todo)
check(task.history.isEmpty, "new task has no history")
task = TaskBoard.move(task, to: .inProgress)
check(task.status == .inProgress, "move changes status")
check(task.history.count == 1 && task.history[0].text.lowercased().contains("in progress"), "move logs history")
let unchanged = TaskBoard.move(task, to: .inProgress)
check(unchanged.history.count == 1, "moving to same status is a no-op")
var overdue = TaskItem(title: "Late", status: .todo, due: Date(timeIntervalSince1970: 0))
check(overdue.isOverdue, "past-due unfinished task is overdue")
overdue = TaskBoard.move(overdue, to: .done)
check(!overdue.isOverdue, "done task is never overdue")

// MARK: Notes
check(NoteText.wordCount("hello world  foo\nbar") == 4, "word count splits on whitespace/newlines")
check(NoteText.inferTitle("# My Title\nbody") == "My Title", "infers title from first heading")
check(NoteText.excerpt("# Heading\n\nThe **body** text here.").contains("body text here"), "excerpt strips markdown & heading")
let note = Note(title: "T", body: String(repeating: "word ", count: 400))
check(note.readingMinutes == 2, "reading time ~200wpm (got \(note.readingMinutes))")

// MARK: Layer placement
let canvas = CGSize(width: 1000, height: 800)
let fitted = LayerPlacement.fittedSize(CGSize(width: 2000, height: 400), canvas: canvas)
check(abs(fitted.width - 550) < 0.001 && abs(fitted.height - 110) < 0.001,
      "large overlay scales to 55% of canvas, keeping aspect (got \(fitted))")
check(LayerPlacement.fittedSize(CGSize(width: 100, height: 50), canvas: canvas) == CGSize(width: 100, height: 50),
      "small overlay is never upscaled")
check(LayerPlacement.fittedSize(.zero, canvas: canvas) == CGSize(width: 24, height: 24),
      "zero-size image falls back to minimum side")
check(LayerPlacement.fittedSize(CGSize(width: 5000, height: 2), canvas: canvas).height == 24,
      "sliver image keeps a grabbable minimum height")

let centered = LayerPlacement.rect(size: CGSize(width: 200, height: 100), centeredAt: CGPoint(x: 500, y: 400), in: canvas)
check(centered == CGRect(x: 400, y: 350, width: 200, height: 100), "rect centres on point")
let edgeDrop = LayerPlacement.rect(size: CGSize(width: 200, height: 100), centeredAt: CGPoint(x: 990, y: -40), in: canvas)
check(edgeDrop == CGRect(x: 800, y: 0, width: 200, height: 100), "drop near edge is pulled fully onto canvas (got \(edgeDrop))")
let oversized = LayerPlacement.rect(size: CGSize(width: 1200, height: 100), centeredAt: CGPoint(x: 500, y: 400), in: canvas)
check(oversized.minX == -100, "wider-than-canvas overlay stays centred instead of clamping")

let size = CGSize(width: 200, height: 100)
let firstRect = LayerPlacement.cascadedRect(size: size, in: canvas, existing: [])
check(firstRect == centered, "first overlay goes to the canvas centre")
let secondRect = LayerPlacement.cascadedRect(size: size, in: canvas, existing: [firstRect])
check(secondRect.minX > firstRect.minX && secondRect.minY > firstRect.minY && secondRect.intersects(firstRect),
      "second overlay cascades down-right and still overlaps the first (got \(secondRect))")
let thirdRect = LayerPlacement.cascadedRect(size: size, in: canvas, existing: [firstRect, secondRect])
check(thirdRect.minX > secondRect.minX, "third overlay cascades past the second")
let movedAway = CGRect(x: 0, y: 0, width: 200, height: 100)
check(LayerPlacement.cascadedRect(size: size, in: canvas, existing: [movedAway]) == centered,
      "centre is reused once the earlier overlay was dragged away")
let full = CGSize(width: 1000, height: 800)
check(LayerPlacement.cascadedRect(size: full, in: canvas, existing: [CGRect(origin: .zero, size: full)]).origin == .zero,
      "canvas-sized overlay with no room to cascade falls back to centre without looping")

var stack = [1, 2, 3]
check(LayerPlacement.bringToFront(&stack, index: 0) && stack == [2, 3, 1], "bringToFront moves item to the end")
check(!LayerPlacement.bringToFront(&stack, index: 2) && stack == [2, 3, 1], "already-front item reports no change")
check(!LayerPlacement.bringToFront(&stack, index: 7), "out-of-range index is ignored")
var empty: [Int] = []
check(!LayerPlacement.bringToFront(&empty, index: 0), "empty stack is a no-op")

// MARK: Audio mixdown
/// Writes a 1-second H.264 clip with `audioTracks` separate AAC tracks (sine tones).
func makeClip(audioTracks: Int) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
    writer.add(video)
    let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
    let audios = (0..<audioTracks).map { _ in AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings) }
    audios.forEach { writer.add($0) }
    writer.startWriting(); writer.startSession(atSourceTime: .zero)

    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
    for frame in 0..<30 {
        while !video.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        if let pixelBuffer { adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) }
    }
    var format = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                             mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                             mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                             mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    var formatDescription: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription)
    for (trackIndex, input) in audios.enumerated() {
        let chunk = 4410
        for start in stride(from: 0, to: 44_100, by: chunk) {
            let frequency = Double(trackIndex + 1) * 440.0
            var samples = (0..<chunk).map { i -> Int16 in
                let phase: Double = Double(start + i) * frequency * 2.0 * Double.pi / 44_100.0
                return Int16(8000.0 * sin(phase))
            }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2,
                                               blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                               dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
            guard let block, let formatDescription else { continue }
            samples.withUnsafeMutableBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                               offsetIntoDestination: 0, dataLength: chunk * 2) }
            var sampleBuffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block,
                                                                 formatDescription: formatDescription, sampleCount: chunk,
                                                                 presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44_100),
                                                                 packetDescriptions: nil, sampleBufferOut: &sampleBuffer)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            if let sampleBuffer { input.append(sampleBuffer) }
        }
    }
    video.markAsFinished(); audios.forEach { $0.markAsFinished() }
    await writer.finishWriting()
    return url
}

/// What a mixed clip contains, as plain values (AVFoundation objects stay inside this function).
struct ClipSummary: Sendable { let audioTracks: Int; let videoTracks: Int; let seconds: Double; let pcm: [Int16] }

func summarize(_ url: URL) async throws -> ClipSummary {
    let asset = AVURLAsset(url: url)
    return ClipSummary(audioTracks: try await asset.loadTracks(withMediaType: .audio).count,
                       videoTracks: try await asset.loadTracks(withMediaType: .video).count,
                       seconds: try await asset.load(.duration).seconds,
                       pcm: try await decodePCM(asset))
}

/// Decode an asset's first audio track to mono Int16 PCM.
func decodePCM(_ asset: AVAsset) async throws -> [Int16] {
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100])
    reader.add(output); reader.startReading()
    var samples: [Int16] = []
    while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
        var chunk = [Int16](repeating: 0, count: CMBlockBufferGetDataLength(block) / 2)
        chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
        samples += chunk
    }
    return samples
}

/// Goertzel power of one frequency in a PCM buffer.
func tonePower(_ samples: [Int16], frequency: Double, sampleRate: Double = 44_100) -> Double {
    let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
    var previous = 0.0, previous2 = 0.0
    for sample in samples {
        let current = Double(sample) + coefficient * previous - previous2
        previous2 = previous; previous = current
    }
    return previous2 * previous2 + previous * previous - coefficient * previous * previous2
}

do {
    let twoTrack = try await makeClip(audioTracks: 2)
    check(try await AudioMixdown.audioTrackCount(of: twoTrack) == 2, "fixture has two audio tracks")
    let mixed = try await AudioMixdown.mixInPlace(twoTrack)
    let after = try await summarize(twoTrack)
    check(mixed, "two-track clip is mixed")
    check(after.audioTracks == 1, "mixed clip has a single audio track")
    check(after.videoTracks == 1, "video track survives the mixdown")
    check(abs(after.seconds - 1) < 0.15, "duration preserved after mixdown (got \(after.seconds)s)")
    let pcm = after.pcm
    let control = tonePower(pcm, frequency: 660)
    check(tonePower(pcm, frequency: 440) > control * 50, "mixed track contains the first source's tone")
    check(tonePower(pcm, frequency: 880) > control * 50, "mixed track contains the second source's tone")

    let oneTrack = try await makeClip(audioTracks: 1)
    let before = try FileManager.default.attributesOfItem(atPath: oneTrack.path)[.modificationDate] as? Date
    check(!(try await AudioMixdown.mixInPlace(oneTrack)), "single-track clip is left alone")
    let unchanged = try FileManager.default.attributesOfItem(atPath: oneTrack.path)[.modificationDate] as? Date
    check(before == unchanged, "single-track file is not rewritten")

    let silent = try await makeClip(audioTracks: 0)
    check(!(try await AudioMixdown.mixInPlace(silent)), "video without audio is left alone")
    [twoTrack, oneTrack, silent].forEach { try? FileManager.default.removeItem(at: $0) }
} catch {
    check(false, "audio mixdown threw: \(error)")
}

// MARK: Coalescing writer
final class ErrorLog: @unchecked Sendable {
    private let lock = NSLock(); private var urls: [URL] = []
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
}
let writerDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-writer-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: writerDir, withIntermediateDirectories: true)
let errors = ErrorLog()
let writer = CoalescingWriter(delay: 0.1) { url, _ in errors.add(url) }
let indexFile = writerDir.appendingPathComponent("index.json")
for value in 1...100 { writer.schedule(indexFile) { Data("\(value)".utf8) } }
try? await Task.sleep(nanoseconds: 400_000_000)
check(writer.writeCount == 1, "100 rapid saves coalesce into one write (got \(writer.writeCount))")
check((try? String(contentsOf: indexFile, encoding: .utf8)) == "100", "coalesced write keeps the latest value")

let tasksFile = writerDir.appendingPathComponent("tasks.json")
writer.schedule(indexFile) { Data("a".utf8) }
writer.schedule(tasksFile) { Data("b".utf8) }
writer.flush()
check(writer.writeCount == 3, "flush writes every pending file immediately (got \(writer.writeCount))")
check((try? String(contentsOf: tasksFile, encoding: .utf8)) == "b", "separate files are written independently")
writer.flush()
check(writer.writeCount == 3, "flush with nothing pending writes nothing")

let missing = writerDir.appendingPathComponent("no-such-dir/x.json")
writer.schedule(missing) { Data("x".utf8) }
writer.flush()
check(errors.count == 1, "failed write is reported, not swallowed")
struct EncodeFailure: Error {}
writer.schedule(indexFile) { throw EncodeFailure() }
writer.flush()
check(errors.count == 2 && (try? String(contentsOf: indexFile, encoding: .utf8)) == "a",
      "encode failure is reported and leaves the previous file intact")
try? FileManager.default.removeItem(at: writerDir)

// MARK: Preferences
enum Flavor: String { case plain, fancy }
if let suite = UserDefaults(suiteName: "snapverify.\(UUID().uuidString)") {
    check(Preference.value("missing", default: true, in: suite), "missing bool falls back to default")
    Preference.set(false, for: "mic", in: suite)
    check(!Preference.value("mic", default: true, in: suite), "stored bool is read back")
    Preference.set(5, for: "delay", in: suite)
    check(Preference.value("delay", default: 0, in: suite) == 5, "stored int is read back")
    check(Preference.value("delay", default: "x", in: suite) == "x", "wrong stored type falls back to default")
    Preference.set(["de-DE"], for: "langs", in: suite)
    check(Preference.value("langs", default: ["en-US"], in: suite) == ["de-DE"], "stored string array is read back")
    Preference.set(Flavor.fancy, for: "flavor", in: suite)
    check(Preference.value("flavor", default: Flavor.plain, in: suite) == .fancy, "stored enum is read back")
    suite.set("removed-case", forKey: "flavor")
    check(Preference.value("flavor", default: Flavor.plain, in: suite) == .plain, "unknown enum raw value falls back")
}

// MARK: Annotation editing
var editDoc = AnnotationDocument()
let arrow = editDoc.add(.arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 40), colorHex: "#FF0000", thickness: 4)
editDoc.translate(id: arrow.id, dx: 1, dy: -10)
check(editDoc.items[0].start == CGPoint(x: 11, y: 0) && editDoc.items[0].end == CGPoint(x: 51, y: 30), "translate moves both endpoints")
editDoc.translate(id: 999, dx: 5, dy: 5)
check(editDoc.items[0].start == CGPoint(x: 11, y: 0), "translate of unknown id is a no-op")

var blue = AnnotationStyle(of: editDoc.items[0]); blue.colorHex = "#0000FF"; blue.thickness = 9
editDoc.restyle(id: arrow.id, to: blue)
check(editDoc.items[0].colorHex == "#0000FF" && editDoc.items[0].thickness == 9, "restyle applies colour and thickness")
check(editDoc.items[0].start == CGPoint(x: 11, y: 0), "restyle keeps geometry")
var ghost = blue; ghost.opacity = 0; ghost.thickness = 0
editDoc.restyle(id: arrow.id, to: ghost)
check(editDoc.items[0].opacity == 0.05 && editDoc.items[0].thickness == 0.5, "restyle clamps opacity and thickness so objects stay selectable")
check(AnnotationStyle(of: editDoc.items[0]).colorHex == "#0000FF", "style round-trips from an annotation")

let stroke = editDoc.addStroke([CGPoint(x: 5, y: 9), CGPoint(x: 20, y: 2), CGPoint(x: 12, y: 30)], style: AnnotationStyle(colorHex: "#00FF00"))
check(stroke?.points.count == 3 && editDoc.items.count == 2, "a pen stroke is one annotation with all its points")
check(stroke?.start == CGPoint(x: 5, y: 2) && stroke?.end == CGPoint(x: 20, y: 30), "stroke bounds span its points")
check(editDoc.addStroke([CGPoint(x: 1, y: 1)], style: AnnotationStyle()) == nil, "single-point stroke is rejected")
check(editDoc.addStroke([], style: AnnotationStyle()) == nil, "empty stroke is rejected")
if let stroke {
    editDoc.translate(id: stroke.id, dx: 10, dy: 10)
    check(editDoc.items[1].points.first == CGPoint(x: 15, y: 19), "translating a stroke moves its points")
}

let copied = editDoc.items[0]
editDoc.remove(id: copied.id)
let pasted = editDoc.insertCopy(of: copied)
check(pasted.id != copied.id && pasted.start == CGPoint(x: copied.start.x + 16, y: copied.start.y + 16),
      "paste after cut inserts an offset copy with a fresh id")
var stepDoc = AnnotationDocument()
let step1 = stepDoc.add(.step, start: .zero, end: .zero)
let step2 = stepDoc.insertCopy(of: step1)
check(step2.stepNumber == 2, "pasted step takes the next number")
check(stepDoc.duplicate(id: 12345) == nil, "duplicate of unknown id returns nil")

var rotateDoc = AnnotationDocument()
_ = rotateDoc.addStroke([CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)], style: AnnotationStyle())
rotateDoc.transformAll { CGPoint(x: -$0.y, y: $0.x) }
check(rotateDoc.items[0].points == [CGPoint(x: -2, y: 1), CGPoint(x: -4, y: 3)], "transformAll maps stroke points too")

if let encoded = try? JSONEncoder().encode(editDoc),
   var decoded = try? JSONDecoder().decode(AnnotationDocument.self, from: encoded) {
    check(decoded.items == editDoc.items, "annotation document round-trips through JSON")
    let next = decoded.add(.rect, start: .zero, end: CGPoint(x: 1, y: 1))
    check(!editDoc.items.map(\.id).contains(next.id), "decoded document keeps issuing unique ids")
} else {
    check(false, "annotation document encodes and decodes")
}

// MARK: Annotation handles
let handleArrow = Annotation(id: 1, tool: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 50))
check(AnnotationHandle.handles(for: handleArrow).map(\.0) == [.start, .end], "arrow exposes start and end handles")
check(AnnotationHandle.hit(CGPoint(x: 98, y: 52), on: handleArrow, tolerance: 6) == .end, "grabbing near the tip picks the end handle")
check(AnnotationHandle.hit(CGPoint(x: 55, y: 30), on: handleArrow, tolerance: 6) == nil, "the middle of an arrow is not a handle")
check(AnnotationHandle.end.dragged(handleArrow, to: CGPoint(x: 200, y: 0)).end == CGPoint(x: 200, y: 0)
      && AnnotationHandle.end.dragged(handleArrow, to: CGPoint(x: 200, y: 0)).start == handleArrow.start,
      "dragging the end handle leaves the start in place")

let box = Annotation(id: 2, tool: .rect, start: CGPoint(x: 50, y: 40), end: CGPoint(x: 10, y: 10))
check(AnnotationHandle.handles(for: box).count == 4, "box shapes expose four corners")
check(AnnotationHandle.hit(CGPoint(x: 11, y: 11), on: box, tolerance: 4) == .topLeft, "corners are found even for a reversed drag")
let grown = AnnotationHandle.bottomRight.dragged(box, to: CGPoint(x: 80, y: 90))
check(selectionRect(from: grown.start, to: grown.end) == CGRect(x: 10, y: 10, width: 70, height: 80),
      "dragging bottom-right resizes against the top-left corner")
let flipped = AnnotationHandle.topLeft.dragged(box, to: CGPoint(x: 70, y: 60))
check(selectionRect(from: flipped.start, to: flipped.end) == CGRect(x: 50, y: 40, width: 20, height: 20),
      "dragging a corner past its opposite flips the box")
let tiny = Annotation(id: 3, tool: .ellipse, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 7, y: 7))
check(AnnotationHandle.hit(CGPoint(x: 7, y: 7), on: tiny, tolerance: 10) == .bottomRight, "overlapping handles pick the nearest")
for tool in [Tool.text, .step, .stamp, .pen] {
    check(AnnotationHandle.handles(for: Annotation(id: 9, tool: tool, start: .zero, end: .zero)).isEmpty,
          "\(tool.rawValue) has no resize handles")
}

// MARK: Editor project files
do {
    let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-project-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let capture = projectRoot.appendingPathComponent("2026-10-13_capture.png")
    let folder = EditorProject.folder(for: capture)
    check(folder.lastPathComponent == "2026-10-13_capture.snappilot", "project folder sits next to the capture")
    check(try EditorProject.load(from: folder) == nil, "a capture without a project loads as nil")

    var projectDoc = AnnotationDocument()
    projectDoc.add(.arrow, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40), colorHex: "#00FF00")
    _ = projectDoc.addStroke([CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)], style: AnnotationStyle())
    let layerInfo = EditorProject.Layer(id: 7, rect: CGRect(x: 3, y: 4, width: 6, height: 4), opacity: 0.5, name: "Logo")
    let project = EditorProject(doc: projectDoc, layers: [layerInfo], framed: true)
    if let base = renderSolid(width: 20, height: 10), let layerImage = renderSolid(width: 6, height: 4) {
        try EditorProject.save(project, base: base, layerImages: [7: layerImage], to: folder)
        let loaded = try EditorProject.load(from: folder)
        check(loaded?.project == project, "project round-trips annotations, layers and frame flag")
        check(loaded?.base.width == 20 && loaded?.base.height == 10, "unannotated base image is restored")
        check(loaded?.layerImages[7]?.width == 6, "layer image is restored")

        var edited = project; edited.framed = false
        try EditorProject.save(edited, base: base, layerImages: [7: layerImage], to: folder)
        check(try EditorProject.load(from: folder)?.project.framed == false, "saving again replaces the previous project")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: projectRoot.path).filter { $0.hasPrefix(".") }
        check(leftovers.isEmpty, "no staging folders are left behind")

        try FileManager.default.removeItem(at: folder.appendingPathComponent("layer-7.png"))
        do { _ = try EditorProject.load(from: folder); check(false, "missing layer image should fail") }
        catch { check((error as? EditorProject.Failure) == .unreadable("layer-7.png"), "missing layer image is reported by name") }

        var future = project; future.version = 99
        try JSONEncoder().encode(future).write(to: folder.appendingPathComponent("project.json"))
        do { _ = try EditorProject.load(from: folder); check(false, "newer project version should fail") }
        catch { check((error as? EditorProject.Failure) == .unsupportedVersion(99), "a newer project version is refused, not misread") }
    }
    try? FileManager.default.removeItem(at: projectRoot)
} catch {
    check(false, "editor project threw: \(error)")
}

// MARK: Snap guides
let snapCanvas = CGSize(width: 1000, height: 600)
let nearCentre = SnapGuides.snap(CGRect(x: 446, y: 200, width: 100, height: 50), to: [], canvas: snapCanvas, threshold: 6)
check(nearCentre.rect.midX == 500, "rect snaps its centre to the canvas centre line (got \(nearCentre.rect.midX))")
check(nearCentre.guides.contains { $0.axis == .vertical && $0.position == 500 }, "centre snap reports a vertical guide")
check(!nearCentre.guides.contains { $0.axis == .horizontal }, "an axis that didn't snap draws no guide")

let farAway = SnapGuides.snap(CGRect(x: 300, y: 200, width: 100, height: 50), to: [], canvas: snapCanvas, threshold: 6)
check(farAway.rect == CGRect(x: 300, y: 200, width: 100, height: 50) && farAway.guides.isEmpty, "nothing within threshold leaves the rect alone")

let neighbour = CGRect(x: 600, y: 100, width: 200, height: 80)
let alignedTop = SnapGuides.snap(CGRect(x: 100, y: 103, width: 120, height: 60), to: [neighbour], canvas: snapCanvas, threshold: 6)
check(alignedTop.rect.minY == 100, "top edge snaps to a neighbour's top edge")
if let guide = alignedTop.guides.first(where: { $0.axis == .horizontal && $0.position == 100 }) {
    check(guide.from == 100 && guide.to == 800, "guide spans from the moving rect to the neighbour (got \(guide.from)…\(guide.to))")
} else { check(false, "neighbour alignment reports a horizontal guide") }

let edge = SnapGuides.snap(CGRect(x: 3, y: 596 - 50, width: 80, height: 50), to: [], canvas: snapCanvas, threshold: 6)
check(edge.rect.minX == 0 && edge.rect.maxY == 600, "rect snaps to canvas left and bottom edges together")
let closest = SnapGuides.snap(CGRect(x: 0, y: 0, width: 10, height: 10), to: [CGRect(x: 14, y: 300, width: 5, height: 5), CGRect(x: 12, y: 400, width: 5, height: 5)],
                              canvas: CGSize(width: 2000, height: 2000), threshold: 6)
check(closest.rect.minX == 0, "an exact match beats a nearby candidate")
let zeroThreshold = SnapGuides.snap(CGRect(x: 1, y: 1, width: 10, height: 10), to: [], canvas: snapCanvas, threshold: 0)
check(zeroThreshold.rect.origin == CGPoint(x: 1, y: 1), "zero threshold disables snapping")

// MARK: Saved styles and restyle-all
var saved = SavedStyles()
let red = AnnotationStyle(colorHex: "#FF0000"), green = AnnotationStyle(colorHex: "#00FF00")
check(saved.styles(for: .arrow).isEmpty, "no saved styles to begin with")
saved.add(red, for: .arrow); saved.add(green, for: .arrow)
check(saved.styles(for: .arrow) == [green, red], "newest saved style comes first")
check(saved.styles(for: .rect).isEmpty, "styles are kept per tool")
saved.add(red, for: .arrow)
check(saved.styles(for: .arrow) == [red, green], "re-saving a style moves it to the front without duplicating")
for i in 0..<20 { saved.add(AnnotationStyle(colorHex: "#0000\(String(format: "%02d", i))"), for: .arrow) }
check(saved.styles(for: .arrow).count == SavedStyles.limitPerTool, "saved styles are capped per tool")
saved.remove(saved.styles(for: .arrow)[0], for: .arrow)
check(saved.styles(for: .arrow).count == SavedStyles.limitPerTool - 1, "a saved style can be removed")
if let data = try? JSONEncoder().encode(saved), let back = try? JSONDecoder().decode(SavedStyles.self, from: data) {
    check(back == saved, "saved styles round-trip through JSON")
} else { check(false, "saved styles encode") }

var typeDoc = AnnotationDocument()
typeDoc.add(.arrow, start: .zero, end: CGPoint(x: 5, y: 5))
typeDoc.add(.arrow, start: .zero, end: CGPoint(x: 9, y: 9), colorHex: "#00FF00")
typeDoc.add(.rect, start: .zero, end: CGPoint(x: 9, y: 9))
check(typeDoc.restyleAll(of: .arrow, to: green) == 1, "restyle-all counts only the annotations that changed")
check(typeDoc.items.filter { $0.tool == .arrow }.allSatisfy { $0.colorHex == "#00FF00" }, "every arrow gets the style")
check(typeDoc.items.first { $0.tool == .rect }?.colorHex == "#FF3B30", "other tools are untouched")
check(typeDoc.restyleAll(of: .step, to: green) == 0, "restyle-all with no matches changes nothing")

// MARK: Canvas expansion
let base100 = CGSize(width: 100, height: 80)
check(LayerPlacement.expansion(canvas: base100, fitting: [CGRect(x: 10, y: 10, width: 20, height: 20)]) == nil,
      "content inside the canvas needs no expansion")
check(LayerPlacement.expansion(canvas: base100, fitting: []) == nil, "no layers needs no expansion")
if let grow = LayerPlacement.expansion(canvas: base100, fitting: [CGRect(x: 90, y: 10, width: 40, height: 20)], padding: 10) {
    check(grow.size == CGSize(width: 140, height: 80) && grow.offset == CGVector(dx: 0, dy: 0),
          "overflow on the right grows width only, plus padding (got \(grow))")
} else { check(false, "right overflow expands") }
if let grow = LayerPlacement.expansion(canvas: base100, fitting: [CGRect(x: -30, y: -5, width: 20, height: 20)]) {
    check(grow.size == CGSize(width: 130, height: 85) && grow.offset == CGVector(dx: 30, dy: 5),
          "overflow left/top grows and shifts existing content (got \(grow))")
} else { check(false, "left/top overflow expands") }
let beside = LayerPlacement.besideRect(size: CGSize(width: 50, height: 120), canvas: base100, gap: 16)
check(beside == CGRect(x: 116, y: 0, width: 50, height: 120), "combined image sits to the right, top-aligned")
if let grow = LayerPlacement.expansion(canvas: base100, fitting: [beside]) {
    check(grow.size == CGSize(width: 166, height: 120), "canvas grows to hold the combined image")
}
if let small = renderSolid(width: 10, height: 10), let big = ImageOps.expanded(small, to: CGSize(width: 30, height: 20), offset: CGVector(dx: 5, dy: 4)) {
    check(big.width == 30 && big.height == 20, "expanded canvas has the new size")
} else { check(false, "expand canvas renders") }
if let small = renderSolid(width: 10, height: 10) {
    check(ImageOps.expanded(small, to: CGSize(width: 5, height: 5), offset: .zero) == nil, "shrinking via expand is refused")
}

// MARK: Rounded corners
func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return pixel[3]
}
if let square = renderSolid(width: 40, height: 40), let rounded = ImageOps.roundedCorners(square, radius: 12) {
    check(alpha(rounded, x: 0, y: 0) == 0, "rounded corner pixel is transparent")
    check(alpha(rounded, x: 20, y: 20) == 255, "centre stays opaque")
    check(alpha(rounded, x: 20, y: 0) == 255, "edge midpoint stays opaque")
    check(ImageOps.roundedCorners(square, radius: 0).map { alpha($0, x: 0, y: 0) } == 255, "zero radius leaves corners square")
    check(ImageOps.roundedCorners(square, radius: 500)?.width == 40, "huge radius is clamped, size unchanged")
}
if let legacy = try? JSONDecoder().decode(EditorProject.self, from: Data(#"{"version":1,"doc":{"items":[],"nextID":1,"nextStep":1},"layers":[],"framed":false}"#.utf8)) {
    check(legacy.cornerRadius == nil, "projects saved before rounded corners still load")
} else { check(false, "legacy project decodes") }

// MARK: Thumbnails
do {
    let thumbDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-thumb-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: thumbDir) }
    func writeFixture(_ name: String, width: Int, height: Int) -> URL? {
        let url = thumbDir.appendingPathComponent(name)
        guard let image = renderSolid(width: width, height: height),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }
    if let wide = writeFixture("wide.png", width: 3000, height: 1500) {
        let thumb = Thumbnail.make(at: wide, maxPixelSize: 600)
        check(thumb?.width == 600 && thumb?.height == 300, "thumbnail fits the longest side, keeping aspect (got \(thumb?.width ?? 0)x\(thumb?.height ?? 0))")
        if let thumb, let full = renderSolid(width: 3000, height: 1500) {
            check(Thumbnail.byteCost(of: thumb) * 20 < Thumbnail.byteCost(of: full), "thumbnail costs a fraction of the full decode")
        }
        check(Thumbnail.make(at: wide, maxPixelSize: 0) == nil, "zero size is rejected")
    }
    if let tall = writeFixture("tall.png", width: 400, height: 2000) {
        check(Thumbnail.make(at: tall, maxPixelSize: 500)?.height == 500, "tall images are limited by height")
    }
    if let small = writeFixture("small.png", width: 120, height: 80) {
        let thumb = Thumbnail.make(at: small, maxPixelSize: 600)
        check(thumb?.width == 120 && thumb?.height == 80, "small images are never upscaled")
    }
    check(Thumbnail.make(at: thumbDir.appendingPathComponent("missing.png"), maxPixelSize: 600) == nil, "missing file returns nil")
    let notImage = thumbDir.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: notImage)
    check(Thumbnail.make(at: notImage, maxPixelSize: 600) == nil, "non-image file returns nil")
} catch {
    check(false, "thumbnail fixtures threw: \(error)")
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
