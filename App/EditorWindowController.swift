import AppKit
import SwiftUI
import CoreGraphics

/// Hosts an `EditorView` in its own window (menu-bar apps have no default window).
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: EditorModel
    var onClose: ((EditorWindowController) -> Void)?

    private static var retainedVideoEditors: [EditorWindowController] = []

    /// Open the editor to annotate a video frame; `onApply` receives the overlay to bake.
    static func presentVideoAnnotate(frame: CGImage, appState: AppState,
                                     onApply: @escaping (CGImage) -> Void) {
        let c = EditorWindowController(image: frame, appState: appState, videoApply: onApply)
        retainedVideoEditors.append(c)
        c.onClose = { ctrl in retainedVideoEditors.removeAll { $0 === ctrl } }
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(image: CGImage, appState: AppState, recordID: String? = nil,
         videoApply: ((CGImage) -> Void)? = nil) {
        self.model = EditorModel(base: image, appState: appState)
        self.model.libraryRecordID = recordID
        self.model.onApplyToVideo = videoApply

        // Open large — a spacious editing surface like Snagit, clamped to the screen.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let contentSize = NSSize(width: min(1360, screen.width * 0.92),
                                 height: min(900, screen.height * 0.9))

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = videoApply == nil ? "Snappilot — Edit" : "Snappilot — Annotate Video"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        let root = EditorView(model: model, onDone: { [weak window] in window?.performClose(nil) })
        window.contentView = NSHostingView(rootView: root.environmentObject(appState))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Reuse this window for a new capture: save the current one first, then swap in the new image.
    func load(image: CGImage, recordID: String?) {
        model.persistToLibrary()
        model.reset(base: image, recordID: recordID)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}
