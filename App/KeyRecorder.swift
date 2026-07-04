import SwiftUI
import AppKit

/// A click-to-record shortcut field. Click it, press a key combo (with modifiers),
/// and it reports the new binding.
struct KeyRecorder: NSViewRepresentable {
    let display: String
    let onCapture: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.onCapture = onCapture
        v.display = display
        return v
    }
    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.onCapture = onCapture
        if !view.recording { view.display = display }
    }
}

final class HotkeyRecorderView: NSView {
    var onCapture: ((HotkeyBinding) -> Void)?
    var display: String = "" { didSet { needsDisplay = true } }
    private(set) var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 26) }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // ESC cancels
            recording = false; window?.makeFirstResponder(nil); return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { NSSound.beep(); return }   // require at least one modifier
        let key = event.charactersIgnoringModifiers ?? ""
        let binding = HotkeyBinding(keyCode: UInt32(event.keyCode),
                                    carbonModifiers: HotkeyBinding.carbonMods(from: flags),
                                    display: HotkeyBinding.displayString(flags: flags, key: key))
        display = binding.display
        onCapture?(binding)
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                   : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? "Type shortcut…" : (display.isEmpty ? "Click to set" : display)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: recording ? NSColor.controlAccentColor
                                        : (display.isEmpty ? NSColor.secondaryLabelColor : NSColor.labelColor),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: r.midX - size.width/2, y: r.midY - size.height/2), withAttributes: attrs)
    }
}
