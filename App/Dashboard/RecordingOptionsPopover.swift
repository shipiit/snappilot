import SwiftUI

/// Every recording setting in one place, opened from the dashboard's Customize button.
struct RecordingOptionsPopover: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recording Options").font(.headline)
            row("System audio", "speaker.wave.2.fill", $app.recordSystemAudio)
            row("Microphone", "mic.fill", $app.recordMic)
            if app.recordMic {
                row("Noise cancellation", "waveform.badge.mic", $app.recordNoiseCancellation).padding(.leading, 18)
            }
            row("Camera overlay", "web.camera.fill", $app.recordCamera)
            row("Show cursor", "cursorarrow", $app.recordCursor)
            row("Cursor highlight & clicks", "cursorarrow.rays", $app.recordCursorHighlight)
            row("Countdown before recording", "timer", $app.recordCountdown)
            Divider()
            HStack {
                Image(systemName: "wand.and.stars").foregroundStyle(.secondary).frame(width: 20)
                Text("Quality").font(.callout)
                Spacer()
                Picker("Quality", selection: $app.recordQuality) {
                    ForEach(RecordQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize()
            }
            Text(app.recordQuality.subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 300)
    }

    private func row(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Label(title, systemImage: icon).font(.callout)
        }
        .toggleStyle(.switch).controlSize(.small)
    }
}
