import AppKit
import CoreGraphics

/// Finds the front-most normal window under a global point, using the window server list.
enum WindowHitTest {
    /// `point` is global bottom-left (as from `NSEvent.mouseLocation`).
    /// Returns the window id and its global **top-left** bounds.
    static func window(at point: CGPoint, excluding overlayWindowNumber: Int?) -> (CGWindowID, CGRect)? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let totalTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let pointTL = CGPoint(x: point.x, y: totalTop - point.y)

        for w in info {
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
            guard layer == 0 else { continue }                       // normal app windows only
            guard let num = w[kCGWindowNumber as String] as? Int else { continue }
            if let overlay = overlayWindowNumber, num == overlay { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"] else { continue }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            if frame.width < 40 || frame.height < 40 { continue }    // skip tiny/utility windows
            if frame.contains(pointTL) {
                return (CGWindowID(num), frame)
            }
        }
        return nil
    }
}
