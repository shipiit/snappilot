import SwiftUI
import SnapCore

/// Screenshot options (Settings › Screenshots).
struct ScreenshotSettingsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("File") {
                Picker("Save captures as", selection: $app.captureFormat) {
                    ForEach(CaptureFormat.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if app.captureFormat.isLossy {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $app.captureQuality, in: 0.5...1).accessibilityLabel("Image quality")
                            Text("\(Int(app.captureQuality * 100))%").monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                Text(formatNote).font(.caption).foregroundStyle(.secondary)
            }
            Section("After capture") {
                Picker("Then", selection: $app.afterCapture) {
                    ForEach(AfterCaptureAction.allCases) { Text($0.title).tag($0) }
                }
                if app.afterCapture == .openEditor {
                    Toggle("Also copy to clipboard", isOn: $app.alsoCopyCapture)
                }
                Toggle("Play shutter sound", isOn: $app.captureSound)
                Text("Every capture is saved to your library either way.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Capturing") {
                Picker("Delay", selection: $app.captureDelay) {
                    Text("None").tag(0); Text("3 seconds").tag(3); Text("5 seconds").tag(5); Text("10 seconds").tag(10)
                }
                Toggle("Show magnifier when selecting a region", isOn: $app.captureMagnifier)
                Toggle("Include mouse pointer", isOn: $app.captureCursor)
                Toggle("Include window shadow", isOn: $app.captureWindowShadow)
                Text("Pointer applies to full-screen and window captures; shadow to window captures.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var formatNote: String {
        switch app.captureFormat {
        case .png: return "Lossless, keeps transparency. Largest files."
        case .jpeg: return "Smaller files, opens everywhere. No transparency — clear areas become white."
        case .heic: return "Smallest files, keeps transparency. Some apps and websites can't open HEIC."
        }
    }
}
