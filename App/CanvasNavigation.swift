import AppKit
import SwiftUI

/// Trackpad navigation for the editor canvas: two-finger scroll pans, pinch zooms. Only
/// events over the canvas are taken, so the Recent tray and side panels keep scrolling.
struct CanvasNavigation: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> NavigationView { NavigationView() }

    func updateNSView(_ view: NavigationView, context: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
    }

    final class NavigationView: NSView {
        var onPan: (CGSize) -> Void = { _ in }
        var onZoom: (CGFloat) -> Void = { _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if event.type == .magnify {
                    self.onZoom(event.magnification)
                } else {
                    self.onPan(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                }
                return nil
            }
        }

        /// Never intercept clicks — the SwiftUI canvas underneath handles them.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
