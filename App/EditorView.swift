import SwiftUI
import CoreGraphics
import SnapCore
import UniformTypeIdentifiers

/// Draw vs. move/select.
enum EditorMode { case draw, select }
private enum LayerResizeHandle { case topLeft, topRight, bottomLeft, bottomRight }

struct EditorView: View {
    @ObservedObject var model: EditorModel
    var onDone: () -> Void

    @State private var mode: EditorMode = .draw
    @State private var draft: (tool: Tool, start: CGPoint, end: CGPoint)?
    @State private var moveAnchor: CGPoint?
    @State private var zoom: CGFloat = 1
    @State private var freehandPoints: [CGPoint] = []
    @State private var showResize = false
    @State private var resizeWidth = ""
    @State private var resizeHeight = ""
    @State private var showOCRTextEditor = false
    @State private var recognizedBoxes: [TextBox] = []
    @State private var recognizedEdits: [String] = []
    @State private var scanningText = false
    @State private var showRecentTray = true
    @State private var activeLayerHandle: LayerResizeHandle?
    @State private var resizeStartRect: CGRect?
    @State private var layerAspectLocked = true

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
        (.spotlight, "light.max", "Spotlight"),
        (.magnify, "plus.magnifyingglass", "Magnify"),
        (.smartMove, "move.3d", "Smart Move"),
        (.crop, "crop", "Crop"),
    ]
    private let stampChoices = ["⭐️", "✅", "❌", "❤️", "🔥", "👍", "⚠️", "💡", "🎯", "🚀", "😀", "🙌"]
    private let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759",
                           "#007AFF", "#AF52DE", "#FF2D55", "#FFFFFF", "#000000"]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                toolSidebar.frame(width: 82)
                Divider()
                VStack(spacing: 0) {
                    topTip
                    canvas
                }
                Divider()
                propertiesPanel.frame(width: 280)
            }
            if showRecentTray {
                Divider()
                editorRecentTray.frame(height: 106)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Theme.appBG)
        .focusable()
        .onKeyPress { press in
            if press.key == .escape {
                model.editingTextID = nil
                model.selectedID = nil
                model.selectedLayerID = nil
                mode = .draw
                return .handled
            }
            if press.characters == "+" || press.characters == "=" {
                zoom = min(3, zoom + 0.1)
                return .handled
            }
            if press.characters == "-" {
                zoom = max(0.25, zoom - 0.1)
                return .handled
            }
            if press.characters == "0" {
                zoom = 1
                return .handled
            }
            guard model.editingTextID == nil,
                  let n = Int(press.characters), (1...9).contains(n), n - 1 < tools.count else { return .ignored }
            model.tool = tools[n - 1].0; mode = .draw
            return .handled
        }
        .onDeleteCommand { model.deleteSelected() }
        .sheet(isPresented: $showResize) { resizeSheet }
        .sheet(isPresented: $showOCRTextEditor) { ocrTextSheet }
        .onReceive(NotificationCenter.default.publisher(for: .snappilotSelectTool)) { note in
            guard let raw = note.object as? String, let tool = Tool(rawValue: raw) else { return }
            selectTool(tool)
        }
        .onReceive(NotificationCenter.default.publisher(for: .snappilotSelectMode)) { _ in
            mode = .select
        }
    }

    private var topTip: some View {
        Text(model.isVideoMode
             ? "Annotate this video frame—drawings and image layers will appear in the time range you selected."
             : "Tip: press 1–9 to switch tools  ·  click Select then drag to move objects")
            .font(.caption)
            .foregroundStyle(model.isVideoMode ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(.bar)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.16)) { showRecentTray.toggle() } } label: {
                Label(showRecentTray ? "Hide Recent" : "Show Recent",
                      systemImage: showRecentTray ? "rectangle.bottomthird.inset.filled" : "clock.arrow.circlepath")
            }.buttonStyle(.borderless).font(.caption)
            Divider().frame(height: 14)
            Text("\(model.base.width) × \(model.base.height)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Text("PNG").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Spacer()
            let objectCount = model.doc.items.count + model.imageLayers.count
            Text("\(objectCount) object\(objectCount == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.tertiary)
            Text("Snappilot").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.bar)
    }

    private var editorRecentTray: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Recent", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("Drag or click to add")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 86, alignment: .leading)
            Divider().padding(.vertical, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 9) {
                    ForEach(AppState.shared.library.records.filter { $0.kind == .image }.prefix(20)) { record in
                        EditorRecentThumbnail(record: record, model: model)
                    }
                }.padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    // MARK: Top toolbar (labeled tools, Snagit-style)
    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).help("Undo")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).help("Redo")
            }.buttonStyle(.borderless)
            Divider().frame(height: 24)
            Text(mode == .select ? "Select" : tools.first(where: { $0.0 == model.tool })?.2 ?? "Annotate")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { chooseOverlayImage() } label: { Label("Add Image", systemImage: "photo.badge.plus") }
                .help("Add a screenshot, logo, or image as a movable overlay")
            Menu {
                Button("Edit Recognized Text…", systemImage: "character.cursor.ibeam") { scanEditableText() }
                Button("Simplify Image", systemImage: "wand.and.stars") { model.simplifyImage() }
                Button("Remove Background", systemImage: "person.crop.rectangle") { model.removeBackground() }
                Button("Blur Background", systemImage: "camera.filters") { model.blurBackground() }
            } label: { Label("Smart", systemImage: "sparkles") }
            Menu {
                Toggle("Polished Frame", systemImage: "square.on.square.dashed", isOn: $model.framed)
                Button("Auto Redact", systemImage: "eye.slash") { model.autoRedact() }
                Button("Grab Text", systemImage: "text.viewfinder") { grabText() }
                Button("Capture Info", systemImage: "info.square") { model.addCaptureInfo() }
            } label: { Label("Effects", systemImage: "camera.filters") }
            Menu {
                Button("Rotate Right", systemImage: "rotate.right") { model.rotateRight() }
                Button("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.flipHorizontal() }
                Button("Resize…", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { prepareResize() }
                Divider()
                Button("Duplicate Selected", systemImage: "plus.square.on.square") { model.duplicateSelected() }
                    .disabled(model.selectedID == nil && model.selectedLayerID == nil)
                Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { model.bringSelectedToFront() }
                    .disabled(model.selectedID == nil && model.selectedLayerID == nil)
                Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { model.sendSelectedToBack() }
                    .disabled(model.selectedID == nil && model.selectedLayerID == nil)
            } label: { Label("Arrange", systemImage: "slider.horizontal.3") }
            Button { copy() } label: { Image(systemName: "doc.on.doc") }.help("Copy")
            Button { share() } label: { Image(systemName: "square.and.arrow.up") }.help("Share")
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.title) { save(format) }
                }
            } label: { Image(systemName: "square.and.arrow.down") }.help("Export")
            Divider().frame(height: 28).padding(.horizontal, 2)
            HStack(spacing: 2) {
                Button { zoom = max(0.25, zoom - 0.1) } label: { Image(systemName: "minus") }
                Text("\(Int(zoom * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 42)
                Button { zoom = min(3, zoom + 0.1) } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.borderless)
            .help("Zoom canvas · + / - / 0")
            Button { zoom = 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.borderless)
                .help("Fit canvas (0 = 100%)")
            Button { done() } label: { Text(model.isVideoMode ? "Apply to Video" : "Done").bold() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private var toolSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 5) {
                sideToolButton(nil, "cursorarrow.rays", "Select", active: mode == .select) { mode = .select }
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 3)
                ForEach(tools, id: \.0) { tool, icon, label in
                    sideToolButton(tool, icon, label,
                                   active: mode == .draw && model.tool == tool) { selectTool(tool) }
                }
            }.padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func sideToolButton(_ tool: Tool?, _ icon: String, _ label: String,
                                active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
                Text(label).font(.system(size: 8, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 35)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(active ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: Canvas
    private var canvas: some View {
        GeometryReader { geo in
            let fit = layout(in: geo.size, zoom: zoom)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)
                Image(nsImage: NSImage(cgImage: model.base, size: model.pixelSize))
                    .resizable()
                    .frame(width: fit.size.width, height: fit.size.height)
                    .offset(x: fit.offset.x, y: fit.offset.y)
                    .shadow(radius: 10)

                Canvas { ctx, _ in
                    for layer in model.imageLayers {
                        let rect = viewRect(layer.rect, fit: fit)
                        var layerContext = ctx
                        layerContext.opacity = layer.opacity
                        layerContext.draw(Image(decorative: layer.image, scale: 1), in: rect)
                    }
                    for a in model.doc.items { drawLive(a, in: ctx, fit: fit) }
                    if let d = draft {
                        let a = Annotation(id: -1, tool: d.tool, start: d.start, end: d.end,
                                           colorHex: model.colorHex, thickness: model.thickness,
                                           stepNumber: d.tool == .step ? model.doc.stepCount + 1 : nil,
                                           filled: model.filled, opacity: model.opacity,
                                           stepStyle: model.stepStyle, lineStyle: model.lineStyle)
                        drawLive(a, in: ctx, fit: fit)
                    }
                    if freehandPoints.count > 1 {
                        for pair in zip(freehandPoints, freehandPoints.dropFirst()) {
                            let segment = Annotation(id: -1, tool: .pen, start: pair.0, end: pair.1,
                                                     colorHex: model.colorHex, thickness: model.thickness,
                                                     opacity: model.opacity, endHead: .none)
                            drawLive(segment, in: ctx, fit: fit)
                        }
                    }
                    if let sel = model.selectedID,
                       let a = model.doc.items.first(where: { $0.id == sel }) {
                        drawSelection(a, in: ctx, fit: fit)
                    }
                    if let selected = model.selectedLayerID,
                       let layer = model.imageLayers.first(where: { $0.id == selected }) {
                        drawLayerSelection(layer.rect, in: ctx, fit: fit)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(fit: fit))

                if let id = model.editingTextID,
                   let a = model.doc.items.first(where: { $0.id == id }) {
                    textEditor(for: a, fit: fit)
                }
            }
            .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: nil) { providers in
                importDroppedImage(providers)
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

                if model.selectedLayerID != nil {
                    Divider()
                    Text(model.selectedLayer?.name.uppercased() ?? "IMAGE OVERLAY")
                        .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    HStack {
                        Button { model.scaleSelectedLayer(by: 0.9) } label: {
                            Label("Smaller", systemImage: "minus.magnifyingglass")
                        }
                        Button { model.scaleSelectedLayer(by: 1.1) } label: {
                            Label("Larger", systemImage: "plus.magnifyingglass")
                        }
                    }.buttonStyle(.bordered)
                    Toggle("Lock aspect ratio", isOn: $layerAspectLocked).font(.caption)
                    if let layer = model.selectedLayer {
                        HStack(spacing: 8) {
                            dimensionField("W", value: layer.rect.width) { width in
                                model.resizeSelectedLayer(to: CGSize(width: width, height: layer.rect.height),
                                                          preserveAspect: layerAspectLocked)
                            }
                            dimensionField("H", value: layer.rect.height) { height in
                                model.resizeSelectedLayer(to: CGSize(width: layer.rect.width, height: height),
                                                          preserveAspect: layerAspectLocked)
                            }
                        }
                    }
                    Button { replaceSelectedOverlay() } label: {
                        Label("Replace Image…", systemImage: "arrow.triangle.2.circlepath")
                    }.buttonStyle(.bordered)
                    HStack(spacing: 6) {
                        Button { model.rotateSelectedLayerRight() } label: { Image(systemName: "rotate.right") }
                            .help("Rotate overlay right")
                        Button { model.flipSelectedLayerHorizontal() } label: { Image(systemName: "arrow.left.and.right") }
                            .help("Flip overlay horizontally")
                        Button { model.fitSelectedLayerToCanvas() } label: { Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left") }
                            .help("Fit overlay to canvas")
                        Button { model.removeSelectedLayerBackground() } label: { Image(systemName: "person.crop.rectangle") }
                            .help("Remove overlay background")
                    }.buttonStyle(.bordered)
                    HStack {
                        Text("Opacity").font(.caption)
                        Slider(value: Binding(
                            get: { model.selectedLayer?.opacity ?? 1 },
                            set: { model.setSelectedLayerOpacity($0) }
                        ), in: 0.05...1, onEditingChanged: { editing in
                            if editing { model.beginTransform() }
                        })
                    }
                    Text("Drag the selected image to position it. You can also drop another image onto the canvas.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo).help("Undo")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.canRedo).help("Redo")
                    Spacer()
                    Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
                        .disabled(model.selectedID == nil && model.selectedLayerID == nil).help("Delete selected")
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
                if mode == .draw && model.tool == .pen {
                    if freehandPoints.isEmpty { freehandPoints = [start] }
                    if let last = freehandPoints.last, hypot(cur.x - last.x, cur.y - last.y) >= 1.5 {
                        freehandPoints.append(cur)
                    }
                } else if mode == .draw { draft = (model.tool, start, cur) }
                else if !handleLayerResize(start: start, current: cur, fit: fit) {
                    handleMove(start: start, current: cur)
                }
            }
            .onEnded { value in
                let start = toImage(value.startLocation, fit: fit)
                let end = toImage(value.location, fit: fit)
                if mode == .draw {
                    draft = nil
                    if model.tool == .pen {
                        model.commitPen(points: freehandPoints)
                        freehandPoints.removeAll()
                        return
                    }
                    let dist = hypot(end.x - start.x, end.y - start.y)
                    if model.tool == .crop {
                        model.crop(start: start, end: end)
                    } else if model.tool == .smartMove {
                        if dist < 4 { model.extractSmartObject(at: start) }
                        else { model.extractForSmartMove(start: start, end: end) }
                        mode = .select
                    } else if model.tool == .step || model.tool == .text || model.tool == .callout || dist >= 3 {
                        model.commit(tool: model.tool, start: start, end: end)
                    }
                } else {
                    if activeLayerHandle != nil {
                        activeLayerHandle = nil; resizeStartRect = nil; moveAnchor = nil
                        return
                    }
                    selectObject(at: start)
                    moveAnchor = nil
                }
            }
    }

    private func handleMove(start: CGPoint, current: CGPoint) {
        if moveAnchor == nil {
            moveAnchor = start
            selectObject(at: start)
            if model.selectedID != nil || model.selectedLayerID != nil { model.beginTransform() }
        }
        guard let anchor = moveAnchor else { return }
        let dx = current.x - anchor.x, dy = current.y - anchor.y
        if let id = model.selectedID { model.move(id: id, dx: dx, dy: dy) }
        else if let id = model.selectedLayerID { model.moveLayer(id: id, dx: dx, dy: dy) }
        moveAnchor = current
    }

    private func handleLayerResize(start: CGPoint, current: CGPoint, fit: Fit) -> Bool {
        if activeLayerHandle == nil {
            guard let id = model.selectedLayerID,
                  let layer = model.imageLayers.first(where: { $0.id == id }),
                  let handle = layerHandle(at: start, rect: layer.rect,
                                           tolerance: max(7, 10 / fit.scale)) else { return false }
            activeLayerHandle = handle; resizeStartRect = layer.rect
            model.beginTransform()
        }
        guard let id = model.selectedLayerID, let handle = activeLayerHandle,
              let original = resizeStartRect else { return false }
        let opposite: CGPoint
        switch handle {
        case .topLeft: opposite = CGPoint(x: original.maxX, y: original.maxY)
        case .topRight: opposite = CGPoint(x: original.minX, y: original.maxY)
        case .bottomLeft: opposite = CGPoint(x: original.maxX, y: original.minY)
        case .bottomRight: opposite = CGPoint(x: original.minX, y: original.minY)
        }
        var width = max(24, abs(current.x - opposite.x))
        var height = max(24, abs(current.y - opposite.y))
        if layerAspectLocked {
            let ratio = original.width / max(1, original.height)
            if width / height > ratio { height = width / ratio } else { width = height * ratio }
        }
        let origin: CGPoint
        switch handle {
        case .topLeft: origin = CGPoint(x: opposite.x - width, y: opposite.y - height)
        case .topRight: origin = CGPoint(x: opposite.x, y: opposite.y - height)
        case .bottomLeft: origin = CGPoint(x: opposite.x - width, y: opposite.y)
        case .bottomRight: origin = opposite
        }
        model.setLayerRect(id: id, rect: CGRect(origin: origin, size: CGSize(width: width, height: height)))
        return true
    }

    private func layerHandle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> LayerResizeHandle? {
        let handles: [(LayerResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        return handles.first { hypot(point.x - $0.1.x, point.y - $0.1.y) <= tolerance }?.0
    }

    private func selectObject(at point: CGPoint) {
        if let id = hitTest(point) {
            model.selectedID = id; model.selectedLayerID = nil
        } else if let id = hitLayer(point) {
            model.selectedLayerID = id; model.selectedID = nil
        } else {
            model.selectedID = nil; model.selectedLayerID = nil
        }
    }

    private func hitTest(_ p: CGPoint) -> Int? {
        for a in model.doc.items.reversed() {
            if boundingRect(a).insetBy(dx: -12, dy: -12).contains(p) { return a.id }
        }
        return nil
    }
    private func hitLayer(_ point: CGPoint) -> Int? {
        model.imageLayers.reversed().first(where: { $0.rect.insetBy(dx: -8, dy: -8).contains(point) })?.id
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
    private func share() { persist(); SystemShare.image(model.exportImage()) }
    private func save(_ format: ExportFormat = .png) {
        if Exporter.save(model.exportImage(), format: format) != nil { persist(); Toast.show("Saved \(format.title)") }
    }

    private func prepareResize() {
        resizeWidth = "\(model.base.width)"; resizeHeight = "\(model.base.height)"; showResize = true
    }

    private func chooseOverlayImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        model.addImageLayer(cgImage); mode = .select
    }

    private func replaceSelectedOverlay() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        model.replaceSelectedLayerImage(cgImage)
    }

    private func dimensionField(_ label: String, value: CGFloat,
                                apply: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            TextField(label, value: Binding<Double>(get: { Double(value) }, set: { apply(CGFloat($0)) }),
                      format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder).frame(width: 72)
            Text("px").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func importDroppedImage(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let image = NSImage(data: data),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                Task { @MainActor in model.addImageLayer(cgImage); mode = .select }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = (item as? URL) ?? (item as? Data).flatMap {
                    String(data: $0, encoding: .utf8).flatMap(URL.init(string:))
                }
                guard let url, let image = NSImage(contentsOf: url),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                Task { @MainActor in model.addImageLayer(cgImage); mode = .select }
            }
            return true
        }
        return false
    }

    private var resizeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resize Image").font(.headline)
            HStack {
                TextField("Width", text: $resizeWidth).frame(width: 100)
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $resizeHeight).frame(width: 100)
                Text("pixels").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showResize = false }.keyboardShortcut(.cancelAction)
                Button("Resize") {
                    if let width = Double(resizeWidth), let height = Double(resizeHeight), width > 0, height > 0 {
                        model.resize(to: CGSize(width: width, height: height)); showResize = false
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 350)
    }

    private func scanEditableText() {
        scanningText = true
        showOCRTextEditor = true
        let image = model.base
        Task {
            recognizedBoxes = (try? await OCR.recognizeBoxes(image, languages: model.appState?.ocrLanguages ?? ["en-US"])) ?? []
            recognizedEdits = recognizedBoxes.map(\.text)
            scanningText = false
        }
    }

    private var ocrTextSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Edit Text in Image").font(.headline)
                    Text("Changed or deleted lines replace the original with a privacy-safe patch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recognizedEdits.joined(separator: "\n"), forType: .string)
                }.disabled(recognizedEdits.isEmpty)
            }.padding()
            Divider()
            if scanningText {
                ProgressView("Recognizing text on this Mac…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if recognizedBoxes.isEmpty {
                ContentUnavailableView("No text found", systemImage: "text.viewfinder")
            } else {
                List(Array(recognizedBoxes.indices), id: \.self) { index in
                    HStack(alignment: .top) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                        TextField("Delete text to remove this line", text: Binding(
                            get: { recognizedEdits.indices.contains(index) ? recognizedEdits[index] : "" },
                            set: { if recognizedEdits.indices.contains(index) { recognizedEdits[index] = $0 } }
                        ), axis: .vertical)
                        Button { recognizedEdits[index] = "" } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete this text from the image")
                    }.padding(.vertical, 3)
                }
            }
            Divider()
            HStack {
                Text("\(recognizedBoxes.count) text region\(recognizedBoxes.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { showOCRTextEditor = false }.keyboardShortcut(.cancelAction)
                Button("Apply Changes") {
                    let edits = recognizedBoxes.indices.compactMap { index -> (box: TextBox, text: String)? in
                        guard recognizedEdits.indices.contains(index), recognizedEdits[index] != recognizedBoxes[index].text else { return nil }
                        return (recognizedBoxes[index], recognizedEdits[index])
                    }
                    model.replaceRecognizedText(edits); showOCRTextEditor = false
                }.buttonStyle(.borderedProminent).disabled(scanningText)
            }.padding()
        }.frame(width: 620, height: 500)
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
    private func layout(in container: CGSize, zoom: CGFloat = 1) -> Fit {
        let iw = model.pixelSize.width, ih = model.pixelSize.height
        guard iw > 0, ih > 0 else { return Fit(scale: 1, offset: .zero, size: .zero) }
        let pad: CGFloat = 28
        let avail = CGSize(width: max(1, container.width - pad * 2), height: max(1, container.height - pad * 2))
        let scale = min(avail.width / iw, avail.height / ih) * zoom
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
    private func viewRect(_ rect: CGRect, fit: Fit) -> CGRect {
        CGRect(x: rect.minX * fit.scale + fit.offset.x, y: rect.minY * fit.scale + fit.offset.y,
               width: rect.width * fit.scale, height: rect.height * fit.scale)
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
        case .spotlight:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.5)))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 8), with: .color(.white), lineWidth: 3)
        case .magnify:
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.2)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 3)
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
        case .crop, .smartMove:
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

    private func drawLayerSelection(_ rect: CGRect, in ctx: GraphicsContext, fit: Fit) {
        let view = viewRect(rect, fit: fit).insetBy(dx: -4, dy: -4)
        ctx.stroke(Path(roundedRect: view, cornerRadius: 4), with: .color(.accentColor),
                   style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        for point in [CGPoint(x: view.minX, y: view.minY), CGPoint(x: view.maxX, y: view.minY),
                      CGPoint(x: view.minX, y: view.maxY), CGPoint(x: view.maxX, y: view.maxY)] {
            ctx.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                     with: .color(.accentColor))
        }
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

extension Notification.Name {
    static let snappilotSelectTool = Notification.Name("SnappilotSelectAnnotationTool")
    static let snappilotSelectMode = Notification.Name("SnappilotSelectMode")
}

private struct EditorRecentThumbnail: View {
    let record: CaptureRecord
    @ObservedObject var model: EditorModel
    @State private var thumbnail: NSImage?

    var body: some View {
        Button { addToCanvas() } label: {
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 7).fill(Theme.panelBG)
                    .frame(width: 112, height: 68)
                    .overlay {
                        if let thumbnail {
                            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                        } else { Image(systemName: "photo").foregroundStyle(.tertiary) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
                Text(record.title).font(.system(size: 8.5)).foregroundStyle(.secondary)
                    .lineLimit(1).frame(width: 112, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .help("Add this capture as a movable image layer")
        .onDrag { NSItemProvider(contentsOf: AppState.shared.library.fileURL(for: record)) ?? NSItemProvider() }
        .task { thumbnail = NSImage(contentsOf: AppState.shared.library.fileURL(for: record)) }
    }

    private func addToCanvas() {
        guard let image = NSImage(contentsOf: AppState.shared.library.fileURL(for: record)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        model.addImageLayer(cgImage)
        Toast.show("Added as image layer", symbol: "photo.on.rectangle")
    }
}
