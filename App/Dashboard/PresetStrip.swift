import AppKit
import SwiftUI

/// Saved one-click capture recipes.
struct PresetStrip: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 10) {
            Text("Presets").font(.system(size: 13, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(app.capturePresets) { preset in
                        Button { app.runPreset(preset) } label: {
                            Label(preset.name + (preset.delay > 0 ? " · \(preset.delay)s" : ""), systemImage: preset.action.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.chipBG, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(preset.action.title)
                        .contextMenu { Button("Delete Preset", role: .destructive) { delete(preset) } }
                    }
                }
            }
            Button { add() } label: { Label("New Preset", systemImage: "plus") }.buttonStyle(.borderless)
        }
    }

    private func add() {
        let alert = NSAlert(); alert.messageText = "New capture preset"
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24)); name.placeholderString = "Preset name"
        alert.accessoryView = name; alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        app.capturePresets.append(CapturePreset(name: value, action: .region)); app.saveCapturePresets()
    }

    private func delete(_ preset: CapturePreset) {
        app.capturePresets.removeAll { $0.id == preset.id }; app.saveCapturePresets()
    }
}
