import SwiftUI

/// Video recording defaults (Settings › Recording).
struct RecordingSettingsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("Video") {
                Picker("Quality", selection: $app.recordQuality) {
                    ForEach(RecordQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text(app.recordQuality.subtitle).font(.caption).foregroundStyle(.secondary)
                Toggle("Show mouse pointer", isOn: $app.recordCursor)
                Toggle("Highlight pointer and clicks", isOn: $app.recordCursorHighlight)
                Toggle("Countdown before recording", isOn: $app.recordCountdown)
            }
            Section("Audio") {
                Toggle("Record system audio", isOn: $app.recordSystemAudio)
                Toggle("Record microphone", isOn: $app.recordMic)
                Toggle("Noise cancellation", isOn: $app.recordNoiseCancellation).disabled(!app.recordMic)
                Text("Microphone and system audio are mixed into one track so every player hears both.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Camera") {
                Toggle("Show webcam overlay", isOn: $app.recordCamera)
                Picker("Background", selection: $app.recordWebcamEffect) {
                    ForEach(WebcamBackgroundEffect.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(!app.recordCamera)
            }
            Section("When a recording ends") {
                Toggle("Open it in the player", isOn: $app.openPlayerAfterRecording)
                Text("Recordings are always saved to your library. Meeting recordings open their notes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
