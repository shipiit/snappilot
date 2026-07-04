import SwiftUI
import AVKit
import AppKit

/// AppKit AVPlayerView wrapper — avoids the SwiftUI `VideoPlayer` (AVKit-SwiftUI) which
/// crashes on generic-metadata instantiation in this configuration.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .inline
        v.showsFullScreenToggleButton = true
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

/// A clean in-app video player for recordings, with export / copy / reveal actions.
struct VideoPreviewView: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(player: player)
                .onAppear { player.play() }
                .onDisappear { player.pause() }
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "video.fill").foregroundStyle(.secondary)
                Text(title).font(.callout).lineLimit(1)
                Spacer()
                Button { exportGIF() } label: { Label("GIF", systemImage: "photo.stack") }
                    .help("Export as animated GIF")
                Button { exportCopy() } label: { Label("Export", systemImage: "square.and.arrow.down") }
                Button { copyFile() } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private func exportCopy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(title).mp4"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
    }

    private func copyFile() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        Toast.show("Copied video")
    }

    private func exportGIF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "\(title).gif"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Toast.show("Exporting GIF…", symbol: "photo.stack")
        Task {
            let ok = await GIFExporter.export(from: url, to: dest)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
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
