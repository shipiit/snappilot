import SwiftUI
import AppKit

/// A "Ready to Record" panel shown after the user picks a recording area — with the
/// capture options and a big Record button (like CleanShot / Snagit).
struct RecordReadyView: View {
    @ObservedObject var app: AppState
    var onRecord: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Ready to Record").font(.title3.bold())

            VStack(spacing: 0) {
                optionRow("cursorarrow", "Cursor", isOn: $app.recordCursor)
                Divider()
                optionRow("speaker.wave.2.fill", "System Audio", isOn: $app.recordSystemAudio)
                Divider()
                optionRow("web.camera.fill", "Webcam", isOn: $app.recordCamera)
                Divider()
                optionRow("mic.fill", "Microphone", isOn: $app.recordMic)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            Toggle("Show countdown before recording", isOn: $app.recordCountdown)
                .toggleStyle(.checkbox).font(.callout)

            HStack(spacing: 12) {
                Button { onCancel() } label: { Text("Cancel").frame(maxWidth: .infinity) }
                    .controlSize(.large).keyboardShortcut(.cancelAction)
                Button { onRecord() } label: {
                    Label("Record", systemImage: "record.circle.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func optionRow(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary).frame(width: 22)
            Text(title).font(.callout)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 9)
    }
}

@MainActor
final class RecordReadyController: NSWindowController {
    private static var current: RecordReadyController?

    static func present(app: AppState, onRecord: @escaping () -> Void, onCancel: @escaping () -> Void) {
        current?.close()
        let c = RecordReadyController(app: app,
            onRecord: { current?.close(); current = nil; onRecord() },
            onCancel: { current?.close(); current = nil; onCancel() })
        current = c
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(app: AppState, onRecord: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .modalPanel
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: RecordReadyView(app: app, onRecord: onRecord, onCancel: onCancel))
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A full-screen 3·2·1 countdown before recording begins.
@MainActor
enum CountdownOverlay {
    private static var window: NSWindow?
    private static var label: NSTextField?
    private static var value = 3
    private static var done: (() -> Void)?
    private static var timer: Timer?

    /// `regionGlobal` is the recorded area in global bottom-left coords; the countdown is
    /// placed *outside* it so it never covers what's being recorded.
    static func show(on screen: NSScreen, regionGlobal: NSRect? = nil,
                     from: Int = 3, completion: @escaping () -> Void) {
        done = completion
        value = max(1, from)

        let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.setFrame(screen.frame, display: true)
        win.level = .screenSaver
        win.backgroundColor = .clear
        win.isOpaque = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let bg = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        bg.wantsLayer = true

        // A compact number pill, positioned outside the region (above it, else below).
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        pill.layer?.cornerRadius = 18
        let side: CGFloat = 96, gap: CGFloat = 16
        var px = screen.frame.width / 2 - side / 2
        var py = screen.frame.height / 2 - side / 2
        if let g = regionGlobal {
            let local = NSRect(x: g.minX - screen.frame.minX, y: g.minY - screen.frame.minY, width: g.width, height: g.height)
            px = min(max(8, local.midX - side / 2), screen.frame.width - side - 8)
            py = local.maxY + gap
            if py + side > screen.frame.height - 8 { py = local.minY - gap - side }   // below if no room above
            py = min(max(8, py), screen.frame.height - side - 8)
        }
        pill.frame = NSRect(x: px, y: py, width: side, height: side)

        let lbl = NSTextField(labelWithString: "\(value)")
        lbl.font = .monospacedDigitSystemFont(ofSize: 60, weight: .bold)
        lbl.textColor = .white
        lbl.alignment = .center
        lbl.frame = NSRect(x: 0, y: side / 2 - 40, width: side, height: 80)
        pill.addSubview(lbl)
        bg.addSubview(pill)
        win.contentView = bg
        win.orderFrontRegardless()

        window = win
        label = lbl

        let t = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { CountdownOverlay.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func tick() {
        value -= 1
        if value <= 0 {
            timer?.invalidate(); timer = nil
            window?.orderOut(nil); window = nil; label = nil
            let c = done; done = nil; c?()
        } else {
            label?.stringValue = "\(value)"
        }
    }
}
