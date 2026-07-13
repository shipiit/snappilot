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

    func beginTrim(_ done: @escaping (Bool) -> Void) {
        playerView.beginTrimming { result in done(result == .okButton) }
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
        let preset = AVAssetExportSession.exportPresets(compatibleWith: asset)
            .contains(AVAssetExportPresetHEVCHighestQuality) ? AVAssetExportPresetHEVCHighestQuality
                                                             : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return false }
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
                Button { AppState.shared.transcribeRecording(url: pc.url, fallbackTitle: title) } label: {
                    Label("Notes", systemImage: "person.2.wave.2.fill")
                }
                .help("Transcribe this recording (on-device) and generate meeting notes")
                Button { annotate() } label: { Label("Annotate", systemImage: "pencil.tip.crop.circle") }
                    .help("Draw on the video — baked in for the whole clip")
                Button { trim() } label: { Label("Trim", systemImage: "scissors") }
                    .help("Trim the start/end, then export the clip")
                Button { exportGIF() } label: { Label("GIF", systemImage: "photo.stack") }
                    .help("Export as animated GIF")
                Button { exportAudio() } label: { Label("Audio", systemImage: "waveform") }
                    .help("Extract the audio track as an .m4a file")
                Button { exportVideo(trimmed: false) } label: { Label("Export", systemImage: "square.and.arrow.down") }
                Button { copyFile() } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { NSWorkspace.shared.activateFileViewerSelecting([pc.url]) } label: {
                    Label("Finder", systemImage: "folder")
                }
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func annotate() {
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
                    let ok = await VideoAnnotator.bake(overlay: overlay, over: pc.url, to: dest)
                    Toast.show(ok ? "Annotated video saved" : "Render failed",
                               symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    if ok { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
                }
            }
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

    private static func extractAudio(from src: URL, to dest: URL) async -> Bool {
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
