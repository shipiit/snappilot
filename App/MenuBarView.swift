import SwiftUI
import SnapCore

/// The menu-bar panel: capture and record tools, recording options and recent captures,
/// styled like the dashboard.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared
    @ObservedObject private var library = AppState.shared.library
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""

    private var results: [CaptureRecord] {
        query.isEmpty ? Array(library.records.prefix(4)) : Array(library.search(query).prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section("Capture") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    tile("Region", "crop", hotkeys.display(.captureRegion), ["#4F46E5", "#6366F1"]) { app.captureRegion() }
                    tile("Window", "macwindow", hotkeys.display(.captureWindow), ["#2563EB", "#3B82F6"]) { app.captureWindow() }
                    tile("Full Screen", "display", hotkeys.display(.captureFull), ["#A21CAF", "#D946EF"]) { app.captureFullScreen() }
                    tile("Grab Text", "text.viewfinder", hotkeys.display(.grabText), ["#059669", "#10B981"]) { app.grabText() }
                    tile("Scrolling", "arrow.down.doc", hotkeys.display(.scrollingCapture), ["#EA580C", "#F97316"]) { app.scrollingCapture() }
                    tile("Webcam", "camera.fill", "", ["#0891B2", "#14B8A6"]) { app.captureWebcamPhoto() }
                }
            }
            section("Record") { recordTools }
            optionChips
            Divider()
            recent
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.appBG)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [hexColor("#4F46E5"), hexColor("#7C3AED")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "camera.viewfinder").foregroundStyle(.white).font(.system(size: 17, weight: .semibold)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Snappilot").font(.system(size: 15, weight: .bold))
                Text("\(library.records.count.formatted()) captures · stored on this Mac")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openDashboard() } label: { Label("Open", systemImage: "macwindow") }
                .buttonStyle(.bordered).controlSize(.small).help("Open the Snappilot dashboard")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: Tools
    private func tile(_ title: String, _ icon: String, _ badge: String, _ colors: [String],
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(height: 20)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Text(badge.isEmpty ? " " : badge).font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(badge.isEmpty ? Color.clear : .white.opacity(0.2), in: Capsule())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(LinearGradient(colors: colors.map(hexColor), startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(badge.isEmpty ? title : "\(title) · \(badge)")
    }

    @ViewBuilder private var recordTools: some View {
        if app.isRecording {
            Button { app.stopRecording() } label: {
                Label(app.isPaused ? "Stop recording (paused)" : "Stop recording", systemImage: "stop.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(hexColor("#DC2626"), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                tile("Region", "record.circle", hotkeys.display(.recordRegion), ["#E11D48", "#F43F5E"]) { app.recordRegion() }
                tile("Screen", "display", hotkeys.display(.recordScreen), ["#DB2777", "#EC4899"]) { app.recordScreen() }
                tile(app.generatingNotes ? "Transcribing…" : "Meeting", "person.2.fill", hotkeys.display(.recordMeeting),
                     ["#4338CA", "#6366F1"]) { app.recordMeeting() }
            }
        }
    }

    private var optionChips: some View {
        HStack(spacing: 6) {
            chip("Audio", on: "speaker.wave.2.fill", off: "speaker.slash.fill", $app.recordSystemAudio)
            chip("Mic", on: "mic.fill", off: "mic.slash.fill", $app.recordMic)
            chip("Camera", on: "web.camera.fill", off: "video.slash.fill", $app.recordCamera)
            Spacer(minLength: 0)
            Text(app.recordQuality.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func chip(_ title: String, on: String, off: String, _ binding: Binding<Bool>) -> some View {
        let isOn = binding.wrappedValue
        return Button { binding.wrappedValue.toggle() } label: {
            Label(title, systemImage: isOn ? on : off)
                .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(isOn ? Color.accentColor.opacity(0.18) : Theme.chipBG, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
        .help("\(title): \(isOn ? "on" : "off")")
    }

    // MARK: Recent
    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                Spacer()
                Button("Show all") { openDashboard() }.buttonStyle(.borderless).font(.system(size: 11))
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search captures & text…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 1))
            if results.isEmpty {
                Text(query.isEmpty ? "No captures yet." : "No matches.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                VStack(spacing: 4) { ForEach(results) { MenuBarRecentRow(record: $0, library: library) } }
            }
        }
    }

    // MARK: Footer
    private var footer: some View {
        HStack(spacing: 14) {
            footerButton("Settings", "gearshape") { openSettings() }
            footerButton("Open File…", "folder") { app.openFilesFromPanel() }
            footerButton("Guide", "questionmark.circle") { WelcomeWindowController.present(app: app) }
            Spacer()
            footerButton("Quit", "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(.secondary)
        }.buttonStyle(.plain)
    }

    private func openDashboard() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A recent capture with a thumbnail. Images open in the editor, videos in the player.
private struct MenuBarRecentRow: View {
    @EnvironmentObject var app: AppState
    let record: CaptureRecord
    @ObservedObject var library: LibraryStore
    @State private var thumb: NSImage?

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5).fill(Theme.panelBG).frame(width: 44, height: 30)
                    .overlay {
                        if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                        else { Image(systemName: record.kind == .video ? "video.fill" : "photo").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.title).font(.system(size: 12)).lineLimit(1)
                    Text("\(record.width)×\(record.height) · \(record.format)").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: record.kind == .video ? "play.fill" : "pencil").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5).padding(.horizontal, 7)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(record.kind == .video ? "Play" : "Open in the editor")
        .contextMenu {
            if record.kind == .image {
                Button("Copy Image", systemImage: "doc.on.doc") {
                    if let image = NSImage(contentsOf: library.fileURL(for: record)) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
                    }
                }
                Button("Open in Preview", systemImage: "eye") { NSWorkspace.shared.open(library.fileURL(for: record)) }
            }
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: record)])
            }
        }
        .task(id: record.fileName) {
            thumb = await ThumbnailCache.shared.thumbnail(for: library.fileURL(for: record), isVideo: record.kind != .image)
        }
    }

    private func open() {
        if record.kind == .video {
            VideoPreviewWindowController.present(url: library.fileURL(for: record), title: record.title)
        } else {
            app.annotateAgain(record)
        }
    }
}
