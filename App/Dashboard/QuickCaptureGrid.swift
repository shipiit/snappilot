import SwiftUI

/// One-click capture tools, five to a row.
struct QuickCaptureGrid: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared
    let openShortcuts: () -> Void

    private struct Tool: Identifiable {
        let title: String, detail: String, icon: String, badge: String, colors: [String]
        let action: () -> Void
        var id: String { title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Capture").font(.system(size: 20, weight: .semibold))
                    Text("One-click tools to capture and extract content.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                delayControl
                Button(action: openShortcuts) { Label("Add shortcut", systemImage: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(tools) { card($0) }
            }
        }
    }

    private var tools: [Tool] {
        [
            Tool(title: "Region", detail: "Capture a specific area of your screen", icon: "crop",
                 badge: hotkeys.display(.captureRegion), colors: ["#4F46E5", "#6366F1"]) { app.captureRegion() },
            Tool(title: "Window", detail: "Capture a specific application window", icon: "macwindow",
                 badge: hotkeys.display(.captureWindow), colors: ["#2563EB", "#3B82F6"]) { app.captureWindow() },
            Tool(title: "Full Screen", detail: "Capture your entire screen", icon: "display",
                 badge: hotkeys.display(.captureFull), colors: ["#A21CAF", "#D946EF"]) { app.captureFullScreen() },
            Tool(title: "Grab Text (OCR)", detail: "Extract text from any area", icon: "text.viewfinder",
                 badge: hotkeys.display(.grabText), colors: ["#059669", "#10B981"]) { app.grabText() },
            Tool(title: "Webcam Photo", detail: "Capture a full-resolution camera still", icon: "camera.fill",
                 badge: "NEW", colors: ["#0891B2", "#14B8A6"]) { app.captureWebcamPhoto() },
            Tool(title: "Scrolling Capture", detail: "Capture a long page into one tall image", icon: "arrow.down.doc",
                 badge: hotkeys.display(.scrollingCapture), colors: ["#EA580C", "#F97316"]) { app.scrollingCapture() },
            Tool(title: "Record Region", detail: "Record a specific area", icon: "record.circle",
                 badge: hotkeys.display(.recordRegion), colors: ["#E11D48", "#F43F5E"]) { app.toggleRecordRegion() },
            Tool(title: "Record Screen", detail: "Record your entire screen", icon: "display",
                 badge: hotkeys.display(.recordScreen), colors: ["#DB2777", "#EC4899"]) { app.toggleRecordScreen() },
            Tool(title: "Record Meeting", detail: "Record a call, then transcribe & get tasks", icon: "person.2.fill",
                 badge: app.generatingNotes ? "Working…" : hotkeys.display(.recordMeeting),
                 colors: ["#4338CA", "#6366F1"]) { app.recordMeeting() },
            Tool(title: "Step Recorder", detail: "Capture every click into a visual guide", icon: "list.number",
                 badge: "Auto", colors: ["#D97706", "#F59E0B"]) { app.startStepRecorder() },
        ]
    }

    private var delayControl: some View {
        HStack(spacing: 8) {
            Text("Delay").font(.system(size: 13))
            Toggle("Delay", isOn: Binding(get: { app.captureDelay > 0 }, set: { app.captureDelay = $0 ? 3 : 0 }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            if app.captureDelay > 0 {
                Picker("Delay length", selection: $app.captureDelay) {
                    Text("3 seconds").tag(3); Text("5 seconds").tag(5); Text("10 seconds").tag(10)
                }.labelsHidden().fixedSize()
            } else {
                Text("Immediate").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 6)
    }

    private func card(_ tool: Tool) -> some View {
        Button(action: tool.action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tool.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tool.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            .minimumScaleFactor(0.8).layoutPriority(1)
                        Spacer(minLength: 2)
                        if !tool.badge.isEmpty {
                            Text(tool.badge).font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(tool.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(LinearGradient(colors: tool.colors.map(hexColor), startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: hexColor(tool.colors[0]).opacity(0.25), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(QuickCaptureButtonStyle())
        .help(tool.detail)
    }
}

/// Lifts slightly on hover and presses down on click.
private struct QuickCaptureButtonStyle: ButtonStyle {
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
