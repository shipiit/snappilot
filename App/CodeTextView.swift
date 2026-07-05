import SwiftUI
import AppKit

/// A plain-text editor backed by NSTextView so we can intercept **paste**: if the clipboard
/// holds an image (e.g. a screenshot), we insert Markdown for it at the caret instead of
/// doing nothing; otherwise normal text paste happens. Used for the notes source editor.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    /// Given a pasted image, return the Markdown to insert (or nil to fall back to text paste).
    var onPasteImage: (NSImage) -> String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = PastingTextView()
        tv.delegate = context.coordinator
        tv.onPasteImage = onPasteImage
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 10, height: 12)
        tv.string = text

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? PastingTextView else { return }
        tv.onPasteImage = onPasteImage
        if tv.string != text { tv.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        init(_ parent: CodeTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

private final class PastingTextView: NSTextView {
    var onPasteImage: ((NSImage) -> String?)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        // Treat as an image paste only when there's an image and no plain text on the board.
        let hasText = pb.string(forType: .string)?.isEmpty == false
        if !hasText,
           let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let markdown = onPasteImage?(image) {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }
}
