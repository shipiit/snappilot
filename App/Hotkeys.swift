import AppKit
import Carbon.HIToolbox

/// Registers global hotkeys via Carbon, reading bindings from `HotkeyStore`.
/// Call `reload()` after any binding changes.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var installed = false

    /// Numeric ids for Carbon, mapped 1:1 with HotkeyAction order.
    private func id(for action: HotkeyAction) -> UInt32 {
        UInt32((HotkeyAction.allCases.firstIndex(of: action) ?? 0) + 1)
    }

    private func handler(for action: HotkeyAction) -> () -> Void {
        switch action {
        case .captureRegion: return { DispatchQueue.main.async { AppState.shared.captureRegion() } }
        case .captureWindow: return { DispatchQueue.main.async { AppState.shared.captureWindow() } }
        case .captureFull:   return { DispatchQueue.main.async { AppState.shared.captureFullScreen() } }
        case .grabText:      return { DispatchQueue.main.async { AppState.shared.grabText() } }
        case .scrollingCapture: return { DispatchQueue.main.async { AppState.shared.scrollingCapture() } }
        case .recordRegion:  return { DispatchQueue.main.async { AppState.shared.toggleRecordRegion() } }
        case .recordScreen:  return { DispatchQueue.main.async { AppState.shared.toggleRecordScreen() } }
        case .recordMeeting: return { DispatchQueue.main.async {
            if AppState.shared.isRecording { AppState.shared.stopRecording() } else { AppState.shared.recordMeeting() } } }
        case .stopRecording: return { DispatchQueue.main.async {
            if AppState.shared.isRecording { AppState.shared.stopRecording() } } }
        }
    }

    func reload() {
        install()
        // Unregister everything, then re-add from the store.
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        actions.removeAll()

        for action in HotkeyAction.allCases {
            let binding = HotkeyStore.shared.binding(action)
            register(id: id(for: action), keyCode: binding.keyCode,
                     mods: binding.carbonModifiers, action: handler(for: action))
        }
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            mgr.actions[hkID.id]?()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func register(id: UInt32, keyCode: UInt32, mods: UInt32, action: @escaping () -> Void) {
        actions[id] = action
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x534E4150), id: id)  // 'SNAP'
        RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}
