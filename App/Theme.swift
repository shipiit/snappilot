import SwiftUI
import AppKit

/// A color that resolves differently in light vs. dark appearance.
func dynColor(_ light: String, _ dark: String) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return nsColor(fromHex: isDark ? dark : light)
    })
}

/// Adaptive app chrome colors — clean light theme, rich dark theme.
enum Theme {
    static let appBG        = dynColor("#F4F5F7", "#0E1116")
    static let sidebarBG    = dynColor("#FBFBFD", "#0B0E12")
    static let cardBG       = dynColor("#FFFFFF", "#161B23")
    static let panelBG      = dynColor("#EDEFF2", "#141922")
    static let stroke       = dynColor("#E3E4E8", "#1E2530")
    static let chipBG       = dynColor("#E9EBEF", "#1B2029")
    static let selectedNav  = dynColor("#E7EDFF", "#1C2836")
}
