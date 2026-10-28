import Foundation

/// What happens right after a screenshot is taken.
public enum AfterCaptureAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case openEditor, copyToClipboard, saveOnly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openEditor: return "Open in editor"
        case .copyToClipboard: return "Copy to clipboard"
        case .saveOnly: return "Save to library only"
        }
    }
}

/// Screenshot options read at capture time (also from background capture code).
public struct CaptureSettings: Equatable, Sendable {
    public var includeCursor: Bool
    public var windowShadow: Bool

    public init(includeCursor: Bool = false, windowShadow: Bool = true) {
        self.includeCursor = includeCursor
        self.windowShadow = windowShadow
    }

    public static let cursorKey = "pref.captureCursor"
    public static let shadowKey = "pref.captureWindowShadow"

    public static func current(in store: UserDefaults = .standard) -> CaptureSettings {
        CaptureSettings(includeCursor: Preference.value(cursorKey, default: false, in: store),
                        windowShadow: Preference.value(shadowKey, default: true, in: store))
    }
}
