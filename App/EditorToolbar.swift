import SwiftUI
import SnapCore

struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    @Binding var mode: EditorMode
    var onCopy: () -> Void
    var onSave: () -> Void
    var onGrabText: () -> Void
    var onDone: () -> Void

    private let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759",
                           "#007AFF", "#AF52DE", "#FFFFFF", "#000000"]

    private let tools: [(Tool, String, String)] = [
        (.arrow, "arrow.up.right", "Arrow"),
        (.line, "line.diagonal", "Line"),
        (.rect, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.text, "textformat", "Text"),
        (.step, "1.circle.fill", "Step number"),
        (.highlight, "highlighter", "Highlight"),
        (.blur, "eye.slash", "Blur / redact"),
        (.pen, "pencil.tip", "Pen"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            // Select / move
            Button { mode = (mode == .select) ? .draw : .select } label: {
                Image(systemName: "cursorarrow").frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .background(mode == .select ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .help("Select & move")

            Divider().frame(height: 20)

            ForEach(tools, id: \.0) { t, icon, help in
                Button {
                    model.tool = t; mode = .draw
                } label: {
                    Image(systemName: icon).frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .background(model.tool == t && mode == .draw ? Color.accentColor.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .help(help)
            }

            Divider().frame(height: 20)

            // Color palette
            HStack(spacing: 4) {
                ForEach(palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(nsColor: nsColor(fromHex: hex)))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(model.colorHex == hex ? 0.9 : 0.15),
                                                 lineWidth: model.colorHex == hex ? 2 : 1))
                        .onTapGesture { model.colorHex = hex }
                }
            }

            // Thickness
            Slider(value: $model.thickness, in: 1...12).frame(width: 80)
                .help("Thickness")

            Divider().frame(height: 20)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless).disabled(!model.canUndo).help("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.borderless).disabled(!model.canRedo).help("Redo")
            Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(model.selectedID == nil).help("Delete selected")

            Spacer()

            Button(action: onGrabText) { Label("Grab Text", systemImage: "text.viewfinder") }
                .help("Extract text with OCR")
            Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
            Button(action: onSave) { Label("Save", systemImage: "square.and.arrow.down") }
            Button(action: onDone) { Text("Done") }.keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}
