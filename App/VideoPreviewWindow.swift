import SwiftUI
import AVKit
import AVFoundation
import AppKit

/// Owns the AVPlayer + AVPlayerView so we can drive native trimming and range export.
@MainActor
final class PlayerController: ObservableObject {
    let url: URL
    let player: AVPlayer
    let playerView = AVPlayerView()

    init(url: URL) {
        self.url = url
        player = AVPlayer(url: url)
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
    }

    func play() { player.play() }
    func pause() { player.pause() }

    var canTrim: Bool { playerView.canBeginTrimming }

    func beginTrim(_ done: @escaping @MainActor @Sendable (Bool) -> Void) {
        playerView.beginTrimming { result in
            Task { @MainActor in done(result == .okButton) }
        }
    }

    /// The user-chosen trim range, if any (set by the native trimming UI).
    func trimmedRange() -> CMTimeRange? {
        guard let item = player.currentItem else { return nil }
        let s = item.reversePlaybackEndTime, e = item.forwardPlaybackEndTime
        if s.isValid, e.isValid, CMTimeCompare(e, s) > 0 { return CMTimeRange(start: s, end: e) }
        return nil
    }

    /// Re-encode `range` (or the whole clip) to `dest`. Returns true on success.
    func export(range: CMTimeRange?, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return false }
        try? FileManager.default.removeItem(at: dest)
        session.outputURL = dest
        session.outputFileType = .mp4
        if let range { session.timeRange = range }
        nonisolated(unsafe) let s = session
        return await withCheckedContinuation { cont in
            s.exportAsynchronously { cont.resume(returning: s.status == .completed) }
        }
    }
}

/// AppKit AVPlayerView wrapper — avoids the SwiftUI `VideoPlayer` (AVKit-SwiftUI) crash.
struct PlayerView: NSViewRepresentable {
    let playerView: AVPlayerView
    func makeNSView(context: Context) -> AVPlayerView { playerView }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

/// A clean in-app video player for recordings, with trim / export / GIF / copy.
struct VideoPreviewView: View {
    let title: String
    @StateObject private var pc: PlayerController

    init(url: URL, title: String) {
        self.title = title
        _pc = StateObject(wrappedValue: PlayerController(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(playerView: pc.playerView)
                .onAppear { pc.play() }
                .onDisappear { pc.pause() }
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "video.fill").foregroundStyle(.secondary)
                Text(title).font(.callout).lineLimit(1)
                Spacer()
                Button { exportFrame() } label: { Label("Frame", systemImage: "photo") }
                    .help("Save the current video frame as an image")
                Menu {
                    Button("Whole Video", systemImage: "rectangle.inset.filled") { annotate(range: nil) }
                    Button("Current Moment · 5 seconds", systemImage: "scope") { annotate(range: momentRange()) }
                    Button("From Current Time to End", systemImage: "forward.end") { annotate(range: remainingRange()) }
                    if let range = pc.trimmedRange() {
                        Button("Selected Trim Range", systemImage: "selection.pin.in.out") { annotate(range: range) }
                    }
                } label: { Label("Annotate", systemImage: "pencil.tip.crop.circle") }
                .help("Add drawings, text, callouts, blur, or image overlays for a chosen time range")
                Button { trim() } label: { Label("Trim", systemImage: "scissors") }
                    .help("Trim the start/end, then export the clip")
                Menu {
                    Button("MP4 Video", systemImage: "film") { exportVideo(trimmed: false) }
                    Button("Animated GIF", systemImage: "photo.stack") { exportGIF() }
                    Button("Audio Only", systemImage: "waveform") { exportAudio() }
                } label: { Label("Export", systemImage: "square.and.arrow.down") }
                Menu {
                    Button("Generate Notes", systemImage: "person.2.wave.2.fill") {
                        AppState.shared.transcribeRecording(url: pc.url, fallbackTitle: title)
                    }
                    Button("Combine Clips…", systemImage: "square.stack.3d.forward.dottedline") { combineClips() }
                    Button("Copy Video", systemImage: "doc.on.doc") { copyFile() }
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([pc.url])
                    }
                    Divider()
                    Menu("Playback Speed", systemImage: "speedometer") {
                        Button("0.5×") { pc.player.rate = 0.5 }
                        Button("1×") { pc.player.rate = 1 }
                        Button("1.5×") { pc.player.rate = 1.5 }
                        Button("2×") { pc.player.rate = 2 }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func annotate(range: CMTimeRange?) {
        pc.pause()
        let time = pc.player.currentTime()
        Toast.show("Opening the current frame to annotate…", symbol: "pencil.tip.crop.circle")
        Task {
            guard let frame = await VideoAnnotator.grabFrame(from: pc.url, at: time) else {
                Toast.show("Couldn't read the video", symbol: "exclamationmark.triangle.fill"); return
            }
            EditorWindowController.presentVideoAnnotate(frame: frame, appState: .shared) { overlay in
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.mpeg4Movie]
                panel.nameFieldStringValue = "\(title)-annotated.mp4"
                guard panel.runModal() == .OK, let dest = panel.url else { return }
                Toast.show("Rendering annotated video…", symbol: "gearshape")
                Task {
                    let ok = await VideoAnnotator.bake(overlay: overlay, over: pc.url, to: dest,
                                                       visibleRange: range)
                    Toast.show(ok ? "Annotated video saved" : "Render failed",
                               symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    if ok { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
                }
            }
        }
    }

    private func momentRange() -> CMTimeRange {
        let duration = pc.player.currentItem?.duration.seconds ?? 0
        let start = max(0, pc.player.currentTime().seconds - 2.5)
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           duration: CMTime(seconds: min(5, max(0, duration - start)), preferredTimescale: 600))
    }

    private func remainingRange() -> CMTimeRange {
        let start = max(0, pc.player.currentTime().seconds)
        let duration = pc.player.currentItem?.duration.seconds ?? start
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           duration: CMTime(seconds: max(0, duration - start), preferredTimescale: 600))
    }

    private func exportFrame() {
        pc.pause(); let time = pc.player.currentTime()
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(title)-frame.png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            guard let frame = await VideoAnnotator.grabFrame(from: pc.url, at: time),
                  let data = Exporter.data(frame, format: .png) else {
                Toast.show("Couldn't save frame", symbol: "exclamationmark.triangle.fill"); return
            }
            do {
                try data.write(to: destination, options: .atomic)
                Toast.show("Frame saved", symbol: "checkmark.circle.fill")
            } catch { Toast.show("Couldn't save frame", symbol: "exclamationmark.triangle.fill") }
        }
    }

    private func trim() {
        guard pc.canTrim else { Toast.show("Can't trim this clip", symbol: "scissors"); return }
        pc.beginTrim { ok in
            if ok { exportVideo(trimmed: true) }
        }
    }

    private func exportVideo(trimmed: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = trimmed ? "\(title)-trimmed.mp4" : "\(title).mp4"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Toast.show("Exporting…", symbol: "square.and.arrow.down")
        Task {
            let ok = await pc.export(range: trimmed ? pc.trimmedRange() : nil, to: dest)
            Toast.show(ok ? "Video saved" : "Export failed",
                       symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            if ok { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
        }
    }

    private func combineClips() {
        pc.pause()
        let open = NSOpenPanel()
        open.allowedContentTypes = [.mpeg4Movie, .movie]
        open.allowsMultipleSelection = true
        open.message = "Choose clips to append after this recording"
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }
        let save = NSSavePanel()
        save.allowedContentTypes = [.mpeg4Movie]
        save.nameFieldStringValue = "\(title)-combined.mp4"
        guard save.runModal() == .OK, let destination = save.url else { return }
        Toast.show("Combining \(open.urls.count + 1) clips…", symbol: "square.stack.3d.forward.dottedline")
        let sources = [pc.url] + open.urls
        Task {
            let ok = await VideoComposer.combine(sources, to: destination)
            Toast.show(ok ? "Combined video saved" : "Couldn't combine these clips",
                       symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            if ok { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        }
    }

    private func copyFile() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([pc.url as NSURL])
        Toast.show("Copied video")
    }

    /// Extract the recording's audio into a standalone .m4a file.
    private func exportAudio() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = "\(title).m4a"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Toast.show("Extracting audio…", symbol: "waveform")
        let src = pc.url
        Task {
            let ok = await Self.extractAudio(from: src, to: dest)
            Toast.show(ok ? "Audio saved" : "No audio track to export",
                       symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            if ok { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
        }
    }

    nonisolated private static func extractAudio(from src: URL, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: src)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else { return false }
        try? FileManager.default.removeItem(at: dest)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return false }
        export.outputURL = dest
        export.outputFileType = .m4a
        await export.export()
        return export.status == .completed
    }

    private func exportGIF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "\(title).gif"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Toast.show("Exporting GIF…", symbol: "photo.stack")
        Task {
            let ok = await GIFExporter.export(from: pc.url, to: dest)
            Toast.show(ok ? "GIF saved" : "GIF export failed",
                       symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            if ok { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
        }
    }
}

@MainActor
final class VideoPreviewWindowController: NSWindowController {
    private static var retained: [VideoPreviewWindowController] = []

    static func present(url: URL, title: String) {
        let c = VideoPreviewWindowController(url: url, title: title)
        retained.append(c)
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(url: URL, title: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: VideoPreviewView(url: url, title: title))
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }
}

extension VideoPreviewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        VideoPreviewWindowController.retained.removeAll { $0 === self }
    }
}
