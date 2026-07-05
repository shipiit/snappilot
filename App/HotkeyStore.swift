import AppKit
import Carbon.HIToolbox

/// Every globally-triggerable action.
enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case captureRegion, captureWindow, captureFull, grabText, scrollingCapture
    case recordRegion, recordScreen, recordMeeting, stopRecording

    var id: String { rawValue }
    var title: String {
        switch self {
        case .captureRegion: return "Capture Region"
        case .captureWindow: return "Capture Window"
        case .captureFull: return "Capture Full Screen"
        case .grabText: return "Grab Text (OCR)"
        case .scrollingCapture: return "Scrolling Capture"
        case .recordRegion: return "Record Region"
        case .recordScreen: return "Record Screen"
        case .recordMeeting: return "Record Meeting"
        case .stopRecording: return "Stop Recording"
        }
    }
    var symbol: String {
        switch self {
        case .captureRegion: return "crop"
        case .captureWindow: return "macwindow"
        case .captureFull: return "rectangle.inset.filled"
        case .grabText: return "text.viewfinder"
        case .scrollingCapture: return "arrow.down.doc"
        case .recordRegion: return "record.circle"
        case .recordScreen: return "rectangle.badge.record"
        case .recordMeeting: return "person.2.wave.2.fill"
        case .stopRecording: return "stop.circle"
        }
    }
}

/// A key + modifiers binding, with a precomputed human display string ("⌃⇧1").
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func displayString(flags: NSEvent.ModifierFlags, key: String) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}

/// Persists user-customizable shortcuts and drives (re)registration.
@MainActor
final class HotkeyStore: ObservableObject {
    static let shared = HotkeyStore()

    @Published private(set) var bindings: [HotkeyAction: HotkeyBinding] = [:]
    private let defaultsKey = "hotkeyBindings.v1"

    private static let factory: [HotkeyAction: HotkeyBinding] = {
        let ctrlShift = UInt32(controlKey | shiftKey)
        func b(_ code: Int, _ disp: String) -> HotkeyBinding {
            HotkeyBinding(keyCode: UInt32(code), carbonModifiers: ctrlShift, display: disp)
        }
        return [
            .captureRegion:    b(kVK_ANSI_1, "⌃⇧1"),
            .captureWindow:    b(kVK_ANSI_2, "⌃⇧2"),
            .captureFull:      b(kVK_ANSI_3, "⌃⇧3"),
            .grabText:         b(kVK_ANSI_4, "⌃⇧4"),
            .recordRegion:     b(kVK_ANSI_5, "⌃⇧5"),
            .recordScreen:     b(kVK_ANSI_6, "⌃⇧6"),
            .scrollingCapture: b(kVK_ANSI_7, "⌃⇧7"),
            .recordMeeting:    b(kVK_ANSI_8, "⌃⇧8"),
            .stopRecording:    b(kVK_ANSI_Period, "⌃⇧."),
        ]
    }()

    init() { load() }

    func binding(_ action: HotkeyAction) -> HotkeyBinding {
        bindings[action] ?? HotkeyStore.factory[action]!
    }
    func display(_ action: HotkeyAction) -> String { binding(action).display }

    func set(_ action: HotkeyAction, _ binding: HotkeyBinding) {
        bindings[action] = binding
        save()
        HotkeyManager.shared.reload()
    }

    func resetToDefaults() {
        bindings = HotkeyStore.factory
        save()
        HotkeyManager.shared.reload()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) {
            var result: [HotkeyAction: HotkeyBinding] = [:]
            for (k, v) in decoded { if let a = HotkeyAction(rawValue: k) { result[a] = v } }
            bindings = HotkeyStore.factory.merging(result) { _, user in user }
        } else {
            bindings = HotkeyStore.factory
        }
    }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
