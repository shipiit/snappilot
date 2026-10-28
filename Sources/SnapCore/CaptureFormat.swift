import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The file format captures are saved in to the library.
public enum CaptureFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case png, jpeg, heic

    public var id: String { rawValue }
    public var title: String { self == .jpeg ? "JPEG" : rawValue.uppercased() }
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var isLossy: Bool { self != .png }
    /// PNG and HEIC keep transparency; JPEG cannot.
    public var supportsTransparency: Bool { self != .jpeg }
    var utType: UTType { self == .png ? .png : self == .jpeg ? .jpeg : .heic }

    /// The format a library file is stored in, judged by its extension.
    public init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "heic", "heif": self = .heic
        default: return nil
        }
    }
}

public enum CaptureEncoder {
    public static let defaultQuality = 0.9

    /// Encode `image` in `format`. `quality` (0.1…1) applies to JPEG and HEIC. Transparent
    /// pixels are composited onto white for JPEG, which would otherwise turn them black.
    public static func data(_ image: CGImage, format: CaptureFormat, quality: Double = defaultQuality) -> Data? {
        let source = format.supportsTransparency ? image : (flattenedOnWhite(image) ?? image)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utType.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = format.isLossy
            ? [kCGImageDestinationLossyCompressionQuality: min(1, max(0.1, quality))] : [:]
        CGImageDestinationAddImage(destination, source, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Encode and write atomically. Returns false if encoding or writing failed.
    @discardableResult
    public static func write(_ image: CGImage, format: CaptureFormat, quality: Double = defaultQuality, to url: URL) -> Bool {
        guard let data = data(image, format: format, quality: quality) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
