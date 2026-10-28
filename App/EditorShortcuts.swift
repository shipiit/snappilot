import AppKit
import SwiftUI

/// Object editing shortcuts for the editor window (⌘C, ⌘X, ⌘V, ⌘D, ⌘], ⌘[, ⌘S, ⇧⌘S, ⌥⌘S).
/// ⌘Z / ⇧⌘Z go through Edit › Undo / Redo via the window's undo manager. A local key monitor sees the event before the main menu does, and it steps
/// aside whenever a text field has focus so typing keeps its own undo / copy / paste.
struct EditorShortcuts: NSViewRepresentable {
    let model: EditorModel
    let copyImage: () -> Void
    let exportImage: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.handle = { event in perform(event) }
    }

    /// Returns true when the shortcut was handled.
    @MainActor
    private func perform(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = mods.contains(.shift)
        guard mods.contains(.command), !mods.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if mods.contains(.option) {
            guard key == "s", !shift else { return false }
            model.saveAsNewCapture()   // ⌥⌘S
            return true
        }
        switch (key, shift) {
        case ("c", false):
            if model.copySelection() { Toast.show("Copied object", symbol: "doc.on.doc") } else { copyImage() }
        case ("x", false):
            guard model.cutSelection() else { return false }
            Toast.show("Cut object", symbol: "scissors")
        case ("v", false): if !model.paste() { NSSound.beep() }
        case ("d", false): model.duplicateSelected()
        case ("]", false): model.bringSelectedToFront()
        case ("[", false): model.sendSelectedToBack()
        case ("s", false): model.persistToLibrary(); Toast.show("Saved to library", symbol: "checkmark.circle.fill")
        case ("s", true): exportImage()
        default: return false
        }
        return true
    }

    final class MonitorView: NSView {
        var handle: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !(window.firstResponder is NSText),
                      window.attachedSheet == nil else { return event }
                return self.handle(event) ? nil : event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
