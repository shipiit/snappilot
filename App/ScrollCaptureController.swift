import AppKit
import CoreGraphics
import SnapCore

/// Snagit-style scrolling capture: repeatedly screenshots a region while auto-scrolling the
/// content underneath it, then stitches the frames into one tall image. Auto-scroll posts
/// scroll-wheel events, which needs Accessibility permission; without it we still capture the
/// single visible frame.
@MainActor
final class ScrollCaptureController {
    static let shared = ScrollCaptureController()
    private(set) var running = false

    static func accessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    /// Prompt the user to grant Accessibility (shows the system dialog + opens the pane).
    static func promptAccessibility() {
        // Key is kAXTrustedCheckOptionPrompt; use the literal to stay concurrency-safe.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func start(region: CGRect, on screen: NSScreen, onDone: @escaping (CGImage?) -> Void) {
        guard !running else { return }
        running = true
        // Region center in CoreGraphics global coordinates (origin top-left of primary display).
        let cocoaGlobal = CGPoint(x: screen.frame.minX + region.midX,
                                  y: screen.frame.minY + region.midY)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let target = CGPoint(x: cocoaGlobal.x, y: primaryHeight - cocoaGlobal.y)
        Task { await run(region: region, screen: screen, target: target, onDone: onDone) }
    }

    private func run(region: CGRect, screen: NSScreen, target: CGPoint,
                     onDone: @escaping (CGImage?) -> Void) async {
        var frames: [CGImage] = []
        let maxFrames = 40
        let scrollAmount = Int32(-max(40, region.height * 0.82))     // ~80% of the viewport, downward

        CGWarpMouseCursorPosition(target)
        for _ in 0..<maxFrames {
            do {
                let shot = try await CaptureController.captureRegion(region, on: screen)
                frames.append(shot.image)
            } catch { break }
            if frames.count >= 2, converged(frames[frames.count - 2], frames[frames.count - 1]) { break }
            scroll(by: scrollAmount, at: target)
            try? await Task.sleep(nanoseconds: 500_000_000)          // let the view settle
        }

        running = false
        let stitched = frames.count <= 1 ? frames.first : ScrollStitcher.stitch(frames)
        onDone(stitched)
    }

    /// True when scrolling revealed no new content (we've hit the bottom).
    private func converged(_ a: CGImage, _ b: CGImage) -> Bool {
        let sa = ScrollStitcher.rowSignatures(a), sb = ScrollStitcher.rowSignatures(b)
        let overlap = ScrollStitcher.bestOverlap(prev: sa, next: sb)
        return overlap >= min(sa.count, sb.count) - 4
    }

    private func scroll(by amount: Int32, at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}
