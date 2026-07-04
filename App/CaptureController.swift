@preconcurrency import ScreenCaptureKit
import CoreGraphics
import AppKit
import SnapCore

/// A finished capture: the pixels plus the selection that produced them.
struct CaptureResult {
    let image: CGImage
    let selection: CaptureSelection
}

enum CaptureError: LocalizedError {
    case noDisplay
    case cropFailed
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Couldn't find the display to capture."
        case .cropFailed: return "The selected region was empty."
        }
    }
}

/// Wraps ScreenCaptureKit. Captures a whole display at full (Retina) resolution, or a
/// specific window, and crops to the user's selection using SnapCore geometry.
@MainActor
enum CaptureController {

    /// The backing scale factor for a display id (2.0 on Retina), via its NSScreen.
    static func scale(for displayID: CGDirectDisplayID) -> CGFloat {
        screen(for: displayID)?.backingScaleFactor ?? 2.0
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screenNumber($0) == displayID }
    }

    static func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Capture a full display to a CGImage at full resolution.
    static func captureDisplayImage(_ display: SCDisplay) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let s = scale(for: display.displayID)
        config.width = Int(CGFloat(display.width) * s)
        config.height = Int(CGFloat(display.height) * s)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Capture a single window to a CGImage (transparent outside the window).
    static func captureWindowImage(_ window: SCWindow) async throws -> CGImage {
        try? await Task.sleep(for: .milliseconds(120))
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let s = window.owningApplication.flatMap { _ in NSScreen.main?.backingScaleFactor } ?? 2.0
        config.width = Int(window.frame.width * s)
        config.height = Int(window.frame.height * s)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Full-screen capture of the screen containing `point` (global, bottom-left origin).
    static func captureFullScreen(at point: CGPoint) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
                ?? NSScreen.main,
              let display = content.displays.first(where: { $0.displayID == screenNumber(screen) })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let image = try await captureDisplayImage(display)
        let s = scale(for: display.displayID)
        let sel = CaptureSelection(rect: CGRect(x: 0, y: 0,
                                                width: CGFloat(display.width),
                                                height: CGFloat(display.height)),
                                   displayID: display.displayID, scale: s)
        return CaptureResult(image: image, selection: sel)
    }

    /// Region capture: `rectInScreen` is in the screen's local points, bottom-left origin.
    static func captureRegion(_ rectInScreen: CGRect, on screen: NSScreen) async throws -> CaptureResult {
        // Let the selection overlay fully vanish so it isn't captured.
        try? await Task.sleep(for: .milliseconds(120))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = screenNumber(screen)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let full = try await captureDisplayImage(display)
        let s = scale(for: display.displayID)

        // Convert bottom-left screen-local rect to top-left pixel rect for cropping.
        let pixelRect = pixelCropRect(selection: rectInScreen,
                                      screenHeightPoints: screen.frame.height, scale: s)
        guard let cropped = ImageOps.crop(full, to: pixelRect) else { throw CaptureError.cropFailed }

        let sel = CaptureSelection(rect: rectInScreen, displayID: display.displayID, scale: s)
        return CaptureResult(image: cropped, selection: sel)
    }
}
