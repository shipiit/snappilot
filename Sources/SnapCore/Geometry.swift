import CoreGraphics

/// A user-chosen capture region on a specific display.
public struct CaptureSelection: Equatable, Sendable {
    /// Rect in the display's points, top-left origin.
    public var rect: CGRect
    public var displayID: UInt32
    /// Backing scale factor (2.0 on Retina).
    public var scale: CGFloat
    /// Set when the selection snapped to a specific window.
    public var windowID: UInt32?

    public init(rect: CGRect, displayID: UInt32, scale: CGFloat, windowID: UInt32? = nil) {
        self.rect = rect
        self.displayID = displayID
        self.scale = scale
        self.windowID = windowID
    }

    /// Pixel size of the resulting capture (points × scale), rounded to whole pixels.
    public var pixelSize: CGSize {
        CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
    }

    /// A selection needs at least a 1×1 point area to be usable.
    public var isValid: Bool { rect.width >= 1 && rect.height >= 1 }
}

/// Normalizes a drag between two points into a positive-sized rect.
public func selectionRect(from a: CGPoint, to b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x),
           y: min(a.y, b.y),
           width: abs(a.x - b.x),
           height: abs(a.y - b.y))
}

/// Convert a selection rect given in a screen's **bottom-left** point space into the
/// **top-left pixel** rect used to crop a full-display screenshot.
///
/// - Parameters:
///   - rect: selection in screen-local points, bottom-left origin (AppKit view space).
///   - screenHeightPoints: the screen's height in points.
///   - scale: the display's backing scale factor (2.0 on Retina).
public func pixelCropRect(selection rect: CGRect,
                          screenHeightPoints: CGFloat,
                          scale: CGFloat) -> CGRect {
    let topLeftY = screenHeightPoints - rect.maxY
    return CGRect(x: rect.minX * scale,
                  y: topLeftY * scale,
                  width: rect.width * scale,
                  height: rect.height * scale)
}
