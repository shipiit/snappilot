import SwiftUI

/// Recording toggles at a glance. Each chip switches its option on or off; off chips show a
/// crossed-out icon so state never depends on colour alone.
struct RecordingOptionsBar: View {
    @EnvironmentObject var app: AppState
    @State private var showOptions = false

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text("Recording").font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: app.isRecording ? "record.circle.fill" : "record.circle").foregroundStyle(.red)
            }
            .padding(.trailing, 6)
            chip("Audio", on: "speaker.wave.2.fill", off: "speaker.slash.fill", $app.recordSystemAudio)
            chip("Mic", on: "mic.fill", off: "mic.slash.fill", $app.recordMic)
            chip("Camera", on: "web.camera.fill", off: "video.slash.fill", $app.recordCamera)
            chip("Highlight", on: "cursorarrow.rays", off: "cursorarrow", $app.recordCursorHighlight)
            chip("Countdown", on: "timer", off: "timer", $app.recordCountdown)
            Spacer()
            Menu {
                Picker("Quality", selection: $app.recordQuality) {
                    ForEach(RecordQuality.allCases, id: \.self) { Text("\($0.title) — \($0.subtitle)").tag($0) }
                }.pickerStyle(.inline)
            } label: {
                Text(app.recordQuality.title).font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 8))
            .help("Recording quality")
            Button { showOptions.toggle() } label: { Label("Customize", systemImage: "slider.horizontal.3") }
                .buttonStyle(.bordered)
                .popover(isPresented: $showOptions, arrowEdge: .bottom) { RecordingOptionsPopover() }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
    }

    private func chip(_ title: String, on: String, off: String, _ binding: Binding<Bool>) -> some View {
        let isOn = binding.wrappedValue
        return Button { binding.wrappedValue.toggle() } label: {
            Label(title, systemImage: isOn ? on : off)
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .strikethrough(!isOn && on == off, color: .secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.18) : Theme.chipBG, in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(title): \(isOn ? "on" : "off") — click to turn \(isOn ? "off" : "on")")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
