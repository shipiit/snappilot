import SwiftUI
import SnapCore

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            ScreenshotSettingsTab().tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            RecordingSettingsTab().tabItem { Label("Recording", systemImage: "record.circle") }
            presets.tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 560)
    }

    private var general: some View {
        Form {
            LabeledContent("Appearance") {
                Picker("", selection: $app.appearance) {
                    ForEach(AppearanceMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
            }
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
                    shortcutRow(.captureFull); shortcutRow(.grabText); shortcutRow(.scrollingCapture)
                }
                Section("Record") {
                    shortcutRow(.recordRegion); shortcutRow(.recordScreen)
                    shortcutRow(.recordMeeting); shortcutRow(.stopRecording)
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

    private var presets: some View {
        VStack(spacing: 0) {
            List {
                ForEach($app.capturePresets) { $preset in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            TextField("Preset name", text: $preset.name).font(.headline)
                            Picker("", selection: $preset.action) {
                                ForEach(CapturePresetAction.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                            }.labelsHidden().frame(width: 170)
                            Button(role: .destructive) {
                                app.capturePresets.removeAll { $0.id == preset.id }; app.saveCapturePresets()
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        HStack(spacing: 16) {
                            Picker("Delay", selection: $preset.delay) {
                                Text("Off").tag(0); Text("3 sec").tag(3); Text("5 sec").tag(5); Text("10 sec").tag(10)
                            }.frame(width: 130)
                            if preset.action == .recordRegion || preset.action == .recordScreen {
                                Toggle("Microphone", isOn: $preset.recordMic)
                                Toggle("Webcam", isOn: $preset.recordCamera)
                            }
                        }.font(.caption)
                    }
                    .padding(.vertical, 6)
                    .onChange(of: preset) { app.saveCapturePresets() }
                }
            }
            HStack {
                Text("Presets remember capture mode, delay, microphone, and webcam.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { app.capturePresets.append(CapturePreset(name: "New preset", action: .region)); app.saveCapturePresets() } label: {
                    Label("Add Preset", systemImage: "plus")
                }
                Button("Restore Defaults") { app.capturePresets = CapturePreset.defaults; app.saveCapturePresets() }
            }.padding(12)
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
