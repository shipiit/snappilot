import SwiftUI
import SnapCore

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 300)
    }

    private var general: some View {
        Form {
            LabeledContent("Library folder") {
                HStack {
                    Text(app.library.root.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Open") { app.openLibraryFolder() }
                }
            }
            LabeledContent("OCR language") {
                Picker("", selection: Binding(get: { app.ocrLanguages.first ?? "en-US" },
                                              set: { app.ocrLanguages = [$0] })) {
                    Text("English").tag("en-US")
                    Text("Spanish").tag("es-ES")
                    Text("French").tag("fr-FR")
                    Text("German").tag("de-DE")
                    Text("Chinese").tag("zh-Hans")
                }.labelsHidden().frame(width: 160)
            }
        }.padding()
    }

    private var shortcuts: some View {
        VStack(spacing: 0) {
            Form {
                Section("Capture") {
                    shortcutRow(.captureRegion); shortcutRow(.captureWindow)
                    shortcutRow(.captureFull); shortcutRow(.grabText)
                }
                Section("Record") {
                    shortcutRow(.recordRegion); shortcutRow(.recordScreen); shortcutRow(.stopRecording)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Click a shortcut, then press your key combo. Works from any app.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset to defaults") { hotkeys.resetToDefaults() }.font(.caption)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func shortcutRow(_ action: HotkeyAction) -> some View {
        LabeledContent {
            KeyRecorder(display: hotkeys.display(action)) { binding in
                hotkeys.set(action, binding)
            }
            .frame(width: 130, height: 26)
        } label: {
            Label(action.title, systemImage: action.symbol)
        }
    }

    private var about: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.viewfinder").font(.system(size: 40)).foregroundStyle(.orange)
            Text("Snappilot").font(.title2.bold())
            Text("Open-source screen capture, annotation & OCR for macOS.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("On-device • Private • MIT licensed").font(.caption).foregroundStyle(.tertiary)
        }.padding()
    }
}
