import SwiftUI
import CoreGraphics
import SnapCore

/// Draw vs. move/select.
enum EditorMode { case draw, select }

struct EditorView: View {
    @ObservedObject var model: EditorModel
    var onDone: () -> Void

    @State private var mode: EditorMode = .draw
    @State private var draft: (tool: Tool, start: CGPoint, end: CGPoint)?
    @State private var moveAnchor: CGPoint?

    private let tools: [(Tool, String, String)] = [
        (.arrow, "arrow.up.right", "Arrow"),
        (.text, "textformat", "Text"),
        (.callout, "bubble.left.fill", "Callout"),
        (.rect, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.line, "line.diagonal", "Line"),
        (.step, "number.circle.fill", "Step"),
        (.highlight, "highlighter", "Highlight"),
        (.blur, "eye.slash.fill", "Blur"),
        (.pen, "pencil.tip", "Pen"),
        (.stamp, "face.smiling", "Stamp"),
        (.crop, "crop", "Crop"),
    ]
    private let stampChoices = ["⭐️", "✅", "❌", "❤️", "🔥", "👍", "⚠️", "💡", "🎯", "🚀", "😀", "🙌"]
    private let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759",
                           "#007AFF", "#AF52DE", "#FF2D55", "#FFFFFF", "#000000"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    Divider()
                    topTip
                    canvas
                }
                Divider()
                propertiesPanel.frame(width: 250)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Theme.appBG)
        .focusable()
        .onKeyPress { press in
            guard model.editingTextID == nil,
                  let n = Int(press.characters), (1...9).contains(n), n - 1 < tools.count else { return .ignored }
            model.tool = tools[n - 1].0; mode = .draw
            return .handled
        }
        .onDeleteCommand { model.deleteSelected() }
    }

    private var topTip: some View {
        Text("Tip: press 1–9 to switch tools  ·  click Select then drag to move objects")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(.bar)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(model.base.width) × \(model.base.height)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Text("PNG").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Spacer()
            Text("\(model.doc.items.count) annotation\(model.doc.items.count == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.tertiary)
            Text("Snappilot").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: Top toolbar (labeled tools, Snagit-style)
    private var topBar: some View {
        HStack(spacing: 4) {
            toolButton(nil, "cursorarrow.rays", "Select", active: mode == .select) {
                mode = .select
            }
            Divider().frame(height: 34).padding(.horizontal, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tools, id: \.0) { t, icon, label in
                        toolButton(t, icon, label, active: mode == .draw && model.tool == t) {
                            selectTool(t)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Button { model.framed.toggle() } label: {
                Label("Frame", systemImage: "square.on.square.dashed")
            }
            .background(model.framed ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .help("Wrap in a polished gradient frame when saving/copying")
            Button { model.autoRedact() } label: { Label("Redact", systemImage: "eye.slash") }
                .help("Auto-blur detected emails & card numbers")
            Button { grabText() } label: { Label("Grab Text", systemImage: "text.viewfinder") }
            Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
            Button { done() } label: { Text(model.isVideoMode ? "Apply to Video" : "Done").bold() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func toolButton(_ tool: Tool?, _ icon: String, _ label: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 9, weight: .medium))
            }
            .frame(width: 52, height: 42)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: Canvas
    private var canvas: some View {
        GeometryReader { geo in
            let fit = layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)
                Image(nsImage: NSImage(cgImage: model.base, size: model.pixelSize))
                    .resizable()
                    .frame(width: fit.size.width, height: fit.size.height)
                    .offset(x: fit.offset.x, y: fit.offset.y)
                    .shadow(radius: 10)

                Canvas { ctx, _ in
                    for a in model.doc.items { drawLive(a, in: ctx, fit: fit) }
                    if let d = draft {
                        let a = Annotation(id: -1, tool: d.tool, start: d.start, end: d.end,
                                           colorHex: model.colorHex, thickness: model.thickness,
                                           stepNumber: d.tool == .step ? model.doc.stepCount + 1 : nil,
                                           filled: model.filled, opacity: model.opacity,
                                           stepStyle: model.stepStyle, lineStyle: model.lineStyle)
                        drawLive(a, in: ctx, fit: fit)
                    }
                    if let sel = model.selectedID,
                       let a = model.doc.items.first(where: { $0.id == sel }) {
                        drawSelection(a, in: ctx, fit: fit)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(fit: fit))

                if let id = model.editingTextID,
                   let a = model.doc.items.first(where: { $0.id == id }) {
                    textEditor(for: a, fit: fit)
                }
            }
        }
    }

    // MARK: Right properties panel
    private var colorBinding: Binding<Color> {
        Binding(get: { Color(nsColor: nsColor(fromHex: model.colorHex)) },
                set: { model.colorHex = hexString(fromNSColor: NSColor($0)) })
    }

    private func selectTool(_ t: Tool) {
        model.tool = t; mode = .draw
        if t == .arrow { model.startHead = .none; model.endHead = .arrow }
        if t == .line { model.startHead = .none; model.endHead = .none }
    }

    private func iconName(for tool: Tool) -> String {
        tools.first(where: { $0.0 == tool })?.1 ?? "circle"
    }

    private var hasQuickStyles: Bool {
        [.arrow, .line, .rect, .ellipse, .step].contains(model.tool)
    }

    /// Per-tool preset grid (10+ each). One click applies a full recipe.
    @ViewBuilder private var quickStylesSection: some View {
        if hasQuickStyles {
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK STYLES").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                let presets = QuickStyle.presets(for: model.tool)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, s in
                        Button { apply(s) } label: {
                            QuickStylePreview(style: s, tool: model.tool)
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(active(s) ? Color.accentColor.opacity(0.22) : Color(nsColor: .controlBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(active(s) ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: active(s) ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func active(_ s: QuickStyle) -> Bool {
        model.colorHex == s.color && model.lineStyle == s.lineStyle && model.filled == s.filled
            && model.startHead == s.startHead && model.endHead == s.endHead
            && (model.tool != .step || model.stepStyle == s.stepStyle)
    }

    private func apply(_ s: QuickStyle) {
        model.colorHex = s.color
        model.lineStyle = s.lineStyle
        model.filled = s.filled
        model.startHead = s.startHead
        model.endHead = s.endHead
        model.stepStyle = s.stepStyle
        if let t = s.thickness { model.thickness = t }
    }

    @ViewBuilder private var stampControl: some View {
        if model.tool == .stamp {
            VStack(alignment: .leading, spacing: 6) {
                Text("STAMP").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(stampChoices, id: \.self) { emoji in
                        Button { model.stamp = emoji } label: {
                            Text(emoji).font(.system(size: 20))
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .background(model.stamp == emoji ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var arrowPropertiesSection: some View {
        if model.tool == .arrow || model.tool == .line {
            Divider()
            Text("ARROW PROPERTIES").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            LabeledContent("Start") {
                Picker("", selection: $model.startHead) {
                    ForEach(ArrowHead.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 100)
            }
            LabeledContent("End") {
                Picker("", selection: $model.endHead) {
                    ForEach(ArrowHead.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 100)
            }
            LabeledContent("Size") {
                Picker("", selection: $model.arrowSize) {
                    ForEach(ArrowSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 100)
            }
        }
    }

    private var tipsBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("TIPS", systemImage: "lightbulb.fill").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text("Select a tool, then click and drag on the image to annotate. Press 1–9 to switch tools.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var stepStyleControl: some View {
        if model.tool == .step {
            VStack(alignment: .leading, spacing: 6) {
                Text("NUMBERING").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Picker("", selection: $model.stepStyle) {
                    Text("1, 2, 3").tag(StepStyle.number)
                    Text("A, B, C").tag(StepStyle.upper)
                    Text("a, b, c").tag(StepStyle.lower)
                }.pickerStyle(.segmented).labelsHidden()
            }
        }
    }

    private var propertiesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                quickStylesSection
                stepStyleControl
                stampControl
                Divider()
                Text("Tool Properties").font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("COLOR").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden().frame(width: 44, height: 26)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(palette, id: \.self) { hex in
                            Circle().fill(Color(nsColor: nsColor(fromHex: hex)))
                                .frame(height: 22)
                                .overlay(Circle().stroke(Color.primary.opacity(model.colorHex == hex ? 0.9 : 0.15),
                                                         lineWidth: model.colorHex == hex ? 2 : 1))
                                .onTapGesture { model.colorHex = hex }
                        }
                    }
                }

                if model.tool == .rect || model.tool == .ellipse {
                    Toggle("Fill shape", isOn: $model.filled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Thickness").font(.caption); Spacer(); Text("\(Int(model.thickness))").font(.caption).foregroundStyle(.secondary) }
                    Slider(value: $model.thickness, in: 1...24)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Opacity").font(.caption); Spacer(); Text("\(Int(model.opacity * 100))%").font(.caption).foregroundStyle(.secondary) }
                    Slider(value: $model.opacity, in: 0.1...1)
                }

                arrowPropertiesSection

                Divider()

                HStack {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo).help("Undo")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.canRedo).help("Redo")
                    Spacer()
                    Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
                        .disabled(model.selectedID == nil).help("Delete selected")
                }
                .buttonStyle(.bordered)

                tipsBox
                Spacer()
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: Gestures
    private func dragGesture(fit: Fit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = toImage(value.startLocation, fit: fit)
                let cur = toImage(value.location, fit: fit)
                if mode == .draw { draft = (model.tool, start, cur) }
                else { handleMove(start: start, current: cur) }
            }
            .onEnded { value in
                let start = toImage(value.startLocation, fit: fit)
                let end = toImage(value.location, fit: fit)
                if mode == .draw {
                    draft = nil
                    let dist = hypot(end.x - start.x, end.y - start.y)
                    if model.tool == .crop {
                        model.crop(start: start, end: end)
                    } else if model.tool == .step || model.tool == .text || model.tool == .callout || dist >= 3 {
                        model.commit(tool: model.tool, start: start, end: end)
                    }
                } else {
                    if let id = hitTest(start) { model.selectedID = id }
                    moveAnchor = nil
                }
            }
    }

    private func handleMove(start: CGPoint, current: CGPoint) {
        if moveAnchor == nil {
            moveAnchor = start
            model.selectedID = hitTest(start) ?? model.selectedID
        }
        guard let id = model.selectedID, let anchor = moveAnchor else { return }
        model.move(id: id, dx: current.x - anchor.x, dy: current.y - anchor.y)
        moveAnchor = current
    }

    private func hitTest(_ p: CGPoint) -> Int? {
        for a in model.doc.items.reversed() {
            if boundingRect(a).insetBy(dx: -12, dy: -12).contains(p) { return a.id }
        }
        return nil
    }
    private func boundingRect(_ a: Annotation) -> CGRect {
        if a.tool == .step || a.tool == .text || a.tool == .stamp {
            let s = max(28, a.thickness * 6)
            return CGRect(x: a.start.x - s, y: a.start.y - s, width: s * 2, height: s * 2)
        }
        return selectionRect(from: a.start, to: a.end)
    }

    // MARK: Actions
    private func done() {
        if let apply = model.onApplyToVideo { apply(model.overlayImage()); onDone(); return }
        persist(); onDone()
    }
    private func copy() { Exporter.copyToPasteboard(model.exportImage()); persist(); Toast.show("Copied to clipboard") }
    private func save() {
        if Exporter.savePNG(model.exportImage()) != nil { persist(); Toast.show("Saved") }
    }

    /// Write the annotated image back into its library record, then refresh OCR for search.
    private func persist() { model.persistToLibrary() }
    private func grabText() {
        Task {
            let lines = (try? await OCR.recognize(model.base, languages: model.appState?.ocrLanguages ?? ["en-US"])) ?? []
            let text = lines.joined(separator: "\n")
            if text.isEmpty { Toast.show("No text found", symbol: "text.viewfinder"); return }
            let pb = NSPasteboard.general; pb.clearContents(); pb.setString(text, forType: .string)
            Toast.show("Copied \(lines.count) line\(lines.count == 1 ? "" : "s")", symbol: "doc.on.clipboard.fill")
        }
    }

    // MARK: Coordinate mapping
    struct Fit { var scale: CGFloat; var offset: CGPoint; var size: CGSize }
    private func layout(in container: CGSize) -> Fit {
        let iw = model.pixelSize.width, ih = model.pixelSize.height
        guard iw > 0, ih > 0 else { return Fit(scale: 1, offset: .zero, size: .zero) }
        let pad: CGFloat = 28
        let avail = CGSize(width: max(1, container.width - pad * 2), height: max(1, container.height - pad * 2))
        let scale = min(avail.width / iw, avail.height / ih)
        let size = CGSize(width: iw * scale, height: ih * scale)
        let offset = CGPoint(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2)
        return Fit(scale: scale, offset: offset, size: size)
    }
    private func toImage(_ v: CGPoint, fit: Fit) -> CGPoint {
        CGPoint(x: (v.x - fit.offset.x) / fit.scale, y: (v.y - fit.offset.y) / fit.scale)
    }
    private func toView(_ p: CGPoint, fit: Fit) -> CGPoint {
        CGPoint(x: p.x * fit.scale + fit.offset.x, y: p.y * fit.scale + fit.offset.y)
    }

    // MARK: Live drawing (view space)
    private func drawLive(_ a: Annotation, in ctx: GraphicsContext, fit: Fit) {
        let color = Color(nsColor: nsColor(fromHex: a.colorHex)).opacity(a.opacity)
        let s = toView(a.start, fit: fit), e = toView(a.end, fit: fit)
        let lw = max(1, a.thickness * fit.scale)
        let dash = a.lineStyle.dashPattern(width: Double(lw)).map { CGFloat($0) }
        let stroke = StrokeStyle(lineWidth: lw, lineCap: .round, dash: dash)
        let rect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
        switch a.tool {
        case .pen:
            var p = Path(); p.move(to: s); p.addLine(to: e)
            ctx.stroke(p, with: .color(color), style: stroke)
        case .line, .arrow:
            var p = Path(); p.move(to: s); p.addLine(to: e)
            ctx.stroke(p, with: .color(color), style: stroke)
            let sz = a.arrowSize.scale
            drawLiveHead(a.startHead, at: s, from: e, width: lw, sizeScale: sz, color: color, in: ctx)
            drawLiveHead(a.endHead, at: e, from: s, width: lw, sizeScale: sz, color: color, in: ctx)
        case .rect:
            if a.filled { ctx.fill(Path(rect), with: .color(color)) }
            else { ctx.stroke(Path(rect), with: .color(color), style: stroke) }
        case .ellipse:
            if a.filled { ctx.fill(Path(ellipseIn: rect), with: .color(color)) }
            else { ctx.stroke(Path(ellipseIn: rect), with: .color(color), style: stroke) }
        case .highlight:
            ctx.fill(Path(rect), with: .color(color.opacity(0.35 * a.opacity)))
        case .blur:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.gray.opacity(0.55)))
            ctx.draw(Text(Image(systemName: "eye.slash.fill")).foregroundColor(.white), at: CGPoint(x: rect.midX, y: rect.midY))
        case .callout:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 10 * fit.scale), with: .color(color))
            ctx.draw(Text(a.text.isEmpty ? "Callout" : a.text)
                        .font(.system(size: max(11, a.thickness * 5 * fit.scale), weight: .semibold))
                        .foregroundColor(.white),
                     at: CGPoint(x: rect.midX, y: rect.midY))
        case .text:
            ctx.draw(Text(a.text.isEmpty ? "Text" : a.text)
                        .font(.system(size: max(12, a.thickness * 6 * fit.scale), weight: .semibold))
                        .foregroundColor(color),
                     at: s, anchor: .topLeading)
        case .step:
            let radius = max(14, a.thickness * 5) * fit.scale
            let r = CGRect(x: s.x - radius, y: s.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: r), with: .color(color))
            ctx.stroke(Path(ellipseIn: r.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white), lineWidth: 2)
            ctx.draw(Text(a.stepLabel).font(.system(size: radius, weight: .bold)).foregroundColor(.white),
                     at: CGPoint(x: s.x, y: s.y))
        case .stamp:
            ctx.draw(Text(a.text.isEmpty ? "⭐️" : a.text)
                        .font(.system(size: max(20, a.thickness * 12 * fit.scale))),
                     at: s, anchor: .center)
        case .crop:
            ctx.stroke(Path(rect), with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            ctx.fill(Path(rect), with: .color(.blue.opacity(0.12)))
        }
    }

    private func drawLiveHead(_ type: ArrowHead, at p: CGPoint, from other: CGPoint,
                              width: CGFloat, sizeScale: Double, color: Color, in ctx: GraphicsContext) {
        guard type != .none else { return }
        let angle = cg_atan2(p.y - other.y, p.x - other.x)
        switch type {
        case .arrow:
            let len = max(10, width * 3.5) * sizeScale, spread = CGFloat.pi / 7
            var path = Path()
            path.move(to: p)
            path.addLine(to: CGPoint(x: p.x - len * cg_cos(angle - spread), y: p.y - len * cg_sin(angle - spread)))
            path.addLine(to: CGPoint(x: p.x - len * cg_cos(angle + spread), y: p.y - len * cg_sin(angle + spread)))
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
        case .dot:
            let r = max(3, width * 1.7) * sizeScale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        case .bar:
            let len = max(6, width * 3) * sizeScale, perp = angle + .pi / 2
            var path = Path()
            path.move(to: CGPoint(x: p.x + len * cg_cos(perp), y: p.y + len * cg_sin(perp)))
            path.addLine(to: CGPoint(x: p.x - len * cg_cos(perp), y: p.y - len * cg_sin(perp)))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        case .none: break
        }
    }

    private func arrowHead(tip: CGPoint, tail: CGPoint, width: CGFloat) -> Path {
        let angle = cg_atan2(tip.y - tail.y, tip.x - tail.x)
        let len = max(10, width * 3.5), spread = CGFloat.pi / 7
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - len * cg_cos(angle - spread), y: tip.y - len * cg_sin(angle - spread)))
        p.addLine(to: CGPoint(x: tip.x - len * cg_cos(angle + spread), y: tip.y - len * cg_sin(angle + spread)))
        p.closeSubpath()
        return p
    }

    private func drawSelection(_ a: Annotation, in ctx: GraphicsContext, fit: Fit) {
        let r = boundingRect(a)
        let v = CGRect(x: r.minX * fit.scale + fit.offset.x, y: r.minY * fit.scale + fit.offset.y,
                       width: r.width * fit.scale, height: r.height * fit.scale).insetBy(dx: -4, dy: -4)
        ctx.stroke(Path(roundedRect: v, cornerRadius: 4), with: .color(.accentColor),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    // MARK: Inline text editing
    @ViewBuilder
    private func textEditor(for a: Annotation, fit: Fit) -> some View {
        let v = toView(a.start, fit: fit)
        TextField(a.tool == .callout ? "Callout text" : "Text", text: Binding(
            get: { a.text },
            set: { model.updateText(id: a.id, $0) }))
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .position(x: v.x + 90, y: v.y + 12)
            .onSubmit { model.editingTextID = nil }
    }
}
