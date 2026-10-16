import SwiftUI
import CoreGraphics
import SnapCore

/// Editor state for one capture: the base image, annotation document, current tool,
/// and undo/redo. Coordinates are in the base image's pixel space (top-left origin).
@MainActor
final class EditorModel: ObservableObject {
    struct ImageLayer: Identifiable {
        let id: Int
        var image: CGImage
        var rect: CGRect
        var opacity: Double = 1
        var name: String = "Image"
    }
    @Published var base: CGImage
    weak var appState: AppState?
    /// The library record this capture belongs to (saved instantly on capture).
    var libraryRecordID: String?

    @Published var doc = AnnotationDocument()
    @Published var tool: Tool = .arrow
    @Published var colorHex = "#FF3B30" { didSet { restyleSelection() } }
    @Published var thickness: Double = 4 { didSet { restyleSelection() } }
    @Published var filled = false { didSet { restyleSelection() } }
    @Published var opacity: Double = 1 { didSet { restyleSelection() } }
    @Published var stepStyle: StepStyle = .number { didSet { restyleSelection() } }
    @Published var lineStyle: LineStyle = .solid { didSet { restyleSelection() } }
    @Published var startHead: ArrowHead = .none { didSet { restyleSelection() } }
    @Published var endHead: ArrowHead = .arrow { didSet { restyleSelection() } }
    @Published var arrowSize: ArrowSize = .medium { didSet { restyleSelection() } }
    @Published var stamp = "⭐️"
    @Published var selectedID: Int? { didSet { if selectedID != oldValue { syncStyleFromSelection() } } }
    @Published var editingTextID: Int?
    @Published var imageLayers: [ImageLayer] = []
    @Published var selectedLayerID: Int?
    private var nextLayerID = 1

    /// A restorable editor state — both the layers and the base image (crop changes base).
    private struct Snapshot { var doc: AnnotationDocument; var base: CGImage; var imageLayers: [ImageLayer] }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// Edits made since the image was last written to the library.
    private(set) var hasUnsavedChanges = false
    /// True while the panel is being loaded from a selection, so it doesn't restyle it back.
    private var isSyncingStyle = false
    /// The selection whose restyle already has an undo snapshot (one undo step per restyle).
    private var restyledSelectionID: Int?

    init(base: CGImage, appState: AppState?) {
        self.base = base
        self.appState = appState
    }

    var pixelSize: CGSize { CGSize(width: base.width, height: base.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Each step can hold a full-size image (after crop/resize/background edits), so history is capped.
    private static let undoLimit = 50

    private func snapshot() {
        undoStack.append(Snapshot(doc: doc, base: base, imageLayers: imageLayers))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
        hasUnsavedChanges = true
        restyledSelectionID = nil
    }

    /// The panel's current style — used for new annotations and for restyling a selection.
    var currentStyle: AnnotationStyle {
        AnnotationStyle(colorHex: colorHex, thickness: thickness, filled: filled, opacity: opacity,
                        stepStyle: stepStyle, lineStyle: lineStyle, startHead: startHead,
                        endHead: endHead, arrowSize: arrowSize)
    }

    /// Selecting an annotation loads its style into the panel.
    private func syncStyleFromSelection() {
        restyledSelectionID = nil
        guard let id = selectedID, let a = doc.items.first(where: { $0.id == id }) else { return }
        isSyncingStyle = true
        defer { isSyncingStyle = false }
        colorHex = a.colorHex; thickness = a.thickness; filled = a.filled; opacity = a.opacity
        stepStyle = a.stepStyle; lineStyle = a.lineStyle
        startHead = a.startHead; endHead = a.endHead; arrowSize = a.arrowSize
    }

    /// Panel edits apply to the selected annotation, Snagit-style.
    private func restyleSelection() {
        guard !isSyncingStyle, let id = selectedID,
              let a = doc.items.first(where: { $0.id == id }) else { return }
        let style = currentStyle
        guard style.applied(to: a) != a else { return }
        if restyledSelectionID != id { snapshot(); restyledSelectionID = id }
        doc.restyle(id: id, to: style)
    }

    /// Commit a finished drag as a new annotation. Returns its id.
    @discardableResult
    func commit(tool: Tool, start: CGPoint, end: CGPoint) -> Int {
        snapshot()
        let text = (tool == .stamp) ? stamp : ""
        let a = doc.add(tool, start: start, end: end, text: text, colorHex: colorHex,
                        thickness: thickness, filled: filled, opacity: opacity,
                        stepStyle: stepStyle, lineStyle: lineStyle,
                        startHead: startHead, endHead: endHead, arrowSize: arrowSize)
        if tool == .text || tool == .callout { editingTextID = a.id; selectedID = a.id }
        return a.id
    }

    /// Crop the base image to a pixel rect (top-left origin) and shift annotations to match.
    func crop(start: CGPoint, end: CGPoint) {
        let r = selectionRect(from: start, to: end)
        guard r.width >= 8, r.height >= 8,
              let cropped = ImageOps.crop(base, to: r) else { return }
        snapshot()
        base = cropped
        doc.translateAll(dx: -r.minX, dy: -r.minY)
        for index in imageLayers.indices {
            imageLayers[index].rect.origin.x -= r.minX
            imageLayers[index].rect.origin.y -= r.minY
        }
        selectedID = nil; selectedLayerID = nil
    }

    func updateText(id: Int, _ text: String) {
        doc.update(id: id) { $0.text = text }
        objectWillChange.send()
    }

    func move(id: Int, dx: CGFloat, dy: CGFloat) {
        doc.translate(id: id, dx: dx, dy: dy)
    }

    func beginTransform() { snapshot() }

    /// Swap in an edited copy of an annotation (same id), e.g. while dragging a handle.
    func replaceAnnotation(_ annotation: Annotation) {
        doc.update(id: annotation.id) { $0 = annotation }
    }

    func extractForSmartMove(start: CGPoint, end: CGPoint) {
        let rect = selectionRect(from: start, to: end).intersection(
            CGRect(x: 0, y: 0, width: base.width, height: base.height)).integral
        guard rect.width >= 8, rect.height >= 8, let crop = ImageOps.crop(base, to: rect),
              let patched = ImageOps.filling(base, rect: rect) else { return }
        snapshot(); base = patched
        let layer = ImageLayer(id: nextLayerID, image: crop, rect: rect); nextLayerID += 1
        imageLayers.append(layer); selectedLayerID = layer.id; selectedID = nil
    }

    func extractSmartObject(at point: CGPoint) {
        let image = compositeBase()
        let languages = appState?.ocrLanguages ?? ["en-US"]
        Toast.show("Detecting UI element…", symbol: "viewfinder")
        Task {
            do {
                guard let rect = try await LocalVisionEdits.smartMoveRect(
                    in: image, at: point, languages: languages) else {
                    Toast.show("No clear object found—drag a box instead", symbol: "viewfinder")
                    return
                }
                extractForSmartMove(start: rect.origin,
                                    end: CGPoint(x: rect.maxX, y: rect.maxY))
                Toast.show("Object ready to move", symbol: "move.3d")
            } catch {
                Toast.show("Object detection failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func moveLayer(id: Int, dx: CGFloat, dy: CGFloat) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[index].rect.origin.x += dx; imageLayers[index].rect.origin.y += dy
    }

    func setLayerRect(id: Int, rect: CGRect) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[index].rect = CGRect(x: rect.minX, y: rect.minY,
                                         width: max(24, rect.width), height: max(24, rect.height))
    }

    func resizeSelectedLayer(to size: CGSize, preserveAspect: Bool) {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        let old = imageLayers[index].rect
        var width = max(24, size.width), height = max(24, size.height)
        if preserveAspect {
            let ratio = old.width / max(1, old.height)
            if abs(width - old.width) >= abs(height - old.height) { height = width / ratio }
            else { width = height * ratio }
        }
        imageLayers[index].rect = CGRect(x: old.midX - width / 2, y: old.midY - height / 2,
                                         width: width, height: height)
    }

    func replaceSelectedLayerImage(_ image: CGImage) {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        snapshot(); imageLayers[index].image = image
        imageLayers[index].name = "Replaced Image"
    }

    func rotateSelectedLayerRight() {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }),
              let image = ImageOps.rotatedRight(imageLayers[index].image) else { return }
        snapshot()
        let old = imageLayers[index].rect
        imageLayers[index].image = image
        imageLayers[index].rect = CGRect(x: old.midX - old.height / 2, y: old.midY - old.width / 2,
                                         width: old.height, height: old.width)
    }

    func flipSelectedLayerHorizontal() {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }),
              let image = ImageOps.flippedHorizontal(imageLayers[index].image) else { return }
        snapshot(); imageLayers[index].image = image
    }

    func fitSelectedLayerToCanvas() {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        let image = imageLayers[index].image
        let factor = min(CGFloat(base.width) / CGFloat(image.width),
                         CGFloat(base.height) / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        imageLayers[index].rect = CGRect(x: (CGFloat(base.width) - size.width) / 2,
                                         y: (CGFloat(base.height) - size.height) / 2,
                                         width: size.width, height: size.height)
    }

    func removeSelectedLayerBackground() {
        guard let id = selectedLayerID,
              let source = imageLayers.first(where: { $0.id == id })?.image else { return }
        Toast.show("Removing overlay background…", symbol: "person.crop.rectangle")
        Task {
            guard let result = try? await LocalVisionEdits.removeBackground(source),
                  let index = imageLayers.firstIndex(where: { $0.id == id }) else {
                Toast.show("No clear foreground found", symbol: "person.crop.rectangle"); return
            }
            snapshot(); imageLayers[index].image = result
            imageLayers[index].name = "Background Removed"
            Toast.show("Overlay background removed", symbol: "checkmark.circle.fill")
        }
    }

    /// Place an external image as a movable overlay on top of everything else. Dropped images
    /// land under the pointer; clicked ones cascade so each new image overlaps the last.
    func addImageLayer(_ image: CGImage, centeredAt point: CGPoint? = nil, clampToCanvas: Bool = true) {
        snapshot()
        let natural = CGSize(width: image.width, height: image.height)
        let size = clampToCanvas ? LayerPlacement.fittedSize(natural, canvas: pixelSize) : natural
        let rect: CGRect
        if let point, !clampToCanvas {
            rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        } else if let point {
            rect = LayerPlacement.rect(size: size, centeredAt: point, in: pixelSize)
        } else {
            rect = LayerPlacement.cascadedRect(size: size, in: pixelSize, existing: imageLayers.map(\.rect))
        }
        let layer = ImageLayer(id: nextLayerID, image: image, rect: rect)
        nextLayerID += 1
        imageLayers.append(layer)
        selectedLayerID = layer.id; selectedID = nil
    }

    func scaleSelectedLayer(by factor: CGFloat) {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        let old = imageLayers[index].rect
        let width = max(24, old.width * factor), height = max(24, old.height * factor)
        imageLayers[index].rect = CGRect(x: old.midX - width / 2, y: old.midY - height / 2,
                                         width: width, height: height)
    }

    func setSelectedLayerOpacity(_ value: Double) {
        guard let id = selectedLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[index].opacity = min(1, max(0.05, value))
    }

    var selectedLayer: ImageLayer? {
        guard let id = selectedLayerID else { return nil }
        return imageLayers.first(where: { $0.id == id })
    }

    func commitPen(points: [CGPoint]) {
        guard points.count > 1 else { return }
        snapshot()
        var style = currentStyle
        style.lineStyle = .solid; style.startHead = .none; style.endHead = .none
        doc.addStroke(points, style: style)
    }

    func duplicateSelected() {
        if let id = selectedLayerID, let source = imageLayers.first(where: { $0.id == id }) {
            snapshot()
            var rect = source.rect; rect.origin.x += 18; rect.origin.y += 18
            let copy = ImageLayer(id: nextLayerID, image: source.image, rect: rect,
                                  opacity: source.opacity, name: source.name + " Copy")
            nextLayerID += 1; imageLayers.append(copy); selectedLayerID = copy.id
        } else if let id = selectedID {
            snapshot(); selectedID = doc.duplicate(id: id)?.id
        }
    }

    /// Select an overlay and raise it above the others, as clicking a window does.
    func focusLayer(id: Int) {
        selectedLayerID = id; selectedID = nil
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        LayerPlacement.bringToFront(&imageLayers, index: index)
    }

    func bringSelectedToFront() {
        if let id = selectedLayerID, let index = imageLayers.firstIndex(where: { $0.id == id }) {
            snapshot(); imageLayers.append(imageLayers.remove(at: index))
        } else if let id = selectedID {
            snapshot(); doc.bringToFront(id: id); objectWillChange.send()
        }
    }

    func sendSelectedToBack() {
        if let id = selectedLayerID, let index = imageLayers.firstIndex(where: { $0.id == id }) {
            snapshot(); imageLayers.insert(imageLayers.remove(at: index), at: 0)
        } else if let id = selectedID {
            snapshot(); doc.sendToBack(id: id); objectWillChange.send()
        }
    }

    func rotateRight() {
        guard let rotated = ImageOps.rotatedRight(base) else { return }
        snapshot()
        let oldHeight = CGFloat(base.height)
        doc.transformAll { CGPoint(x: oldHeight - $0.y, y: $0.x) }
        imageLayers = imageLayers.compactMap { layer in
            guard let image = ImageOps.rotatedRight(layer.image) else { return nil }
            return ImageLayer(id: layer.id, image: image,
                              rect: CGRect(x: oldHeight - layer.rect.maxY, y: layer.rect.minX,
                                           width: layer.rect.height, height: layer.rect.width),
                              opacity: layer.opacity, name: layer.name)
        }
        base = rotated; selectedID = nil; selectedLayerID = nil
    }

    func flipHorizontal() {
        guard let flipped = ImageOps.flippedHorizontal(base) else { return }
        snapshot()
        let width = CGFloat(base.width)
        doc.transformAll { CGPoint(x: width - $0.x, y: $0.y) }
        imageLayers = imageLayers.compactMap { layer in
            guard let image = ImageOps.flippedHorizontal(layer.image) else { return nil }
            return ImageLayer(id: layer.id, image: image,
                              rect: CGRect(x: width - layer.rect.maxX, y: layer.rect.minY,
                                           width: layer.rect.width, height: layer.rect.height),
                              opacity: layer.opacity, name: layer.name)
        }
        base = flipped; selectedID = nil; selectedLayerID = nil
    }

    func resize(to newSize: CGSize) {
        let width = max(1, Int(newSize.width.rounded()))
        let height = max(1, Int(newSize.height.rounded()))
        guard let resized = ImageOps.resized(base, width: width, height: height) else { return }
        snapshot()
        let sx = CGFloat(width) / CGFloat(base.width), sy = CGFloat(height) / CGFloat(base.height)
        doc.transformAll { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        for index in imageLayers.indices {
            let rect = imageLayers[index].rect
            imageLayers[index].rect = CGRect(x: rect.minX * sx, y: rect.minY * sy,
                                              width: rect.width * sx, height: rect.height * sy)
        }
        base = resized; selectedID = nil; selectedLayerID = nil
    }

    func addCaptureInfo() {
        snapshot()
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let text = "Captured \(formatter.string(from: Date()))\n\(base.width) × \(base.height) · \(version)"
        let margin = max(20, CGFloat(base.width) * 0.02)
        let boxWidth = min(CGFloat(base.width) - margin * 2, max(360, CGFloat(base.width) * 0.42))
        let boxHeight = max(72, CGFloat(base.height) * 0.09)
        let annotation = doc.add(.callout,
                                 start: CGPoint(x: margin, y: CGFloat(base.height) - boxHeight - margin),
                                 end: CGPoint(x: margin + boxWidth, y: CGFloat(base.height) - margin),
                                 text: text, colorHex: "#1F2937", thickness: 3,
                                 filled: true, opacity: 0.92)
        selectedID = annotation.id
    }

    func simplifyImage() {
        guard let simplified = LocalVisionEdits.simplify(compositeBase()) else {
            Toast.show("Couldn't simplify this image", symbol: "exclamationmark.triangle.fill"); return
        }
        snapshot()
        let layer = ImageLayer(id: nextLayerID, image: simplified,
                               rect: CGRect(x: 0, y: 0, width: base.width, height: base.height),
                               opacity: 1, name: "Simplify")
        nextLayerID += 1; imageLayers.append(layer)
        selectedID = nil; selectedLayerID = layer.id
        Toast.show("Editable Simplify layer added", symbol: "wand.and.stars")
    }

    func removeBackground() {
        let image = flattened()
        Toast.show("Finding foreground objects…", symbol: "person.crop.rectangle")
        Task {
            do {
                guard let result = try await LocalVisionEdits.removeBackground(image) else {
                    Toast.show("No clear foreground object found", symbol: "person.crop.rectangle"); return
                }
                snapshot(); base = result; doc = AnnotationDocument(); imageLayers.removeAll()
                selectedID = nil; selectedLayerID = nil
                Toast.show("Background removed", symbol: "checkmark.circle.fill")
            } catch {
                Toast.show("Background removal failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func blurBackground() {
        let image = flattened()
        Toast.show("Separating foreground…", symbol: "camera.filters")
        Task {
            do {
                guard let result = try await LocalVisionEdits.blurBackground(image) else {
                    Toast.show("No clear foreground object found", symbol: "camera.filters"); return
                }
                snapshot(); base = result; doc = AnnotationDocument(); imageLayers.removeAll()
                selectedID = nil; selectedLayerID = nil
                Toast.show("Background blurred", symbol: "checkmark.circle.fill")
            } catch {
                Toast.show("Background blur failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func replaceRecognizedText(_ edits: [(box: TextBox, text: String)]) {
        guard !edits.isEmpty else { return }
        snapshot()
        for edit in edits {
            let rect = edit.box.rect.insetBy(dx: -3, dy: -2)
            let background = ImageOps.surroundingColor(base, rect: rect)
            if let patched = ImageOps.filling(base, rect: rect, color: background) { base = patched }
            if !edit.text.isEmpty {
                let components = background.components ?? [1, 1, 1, 1]
                let red = components.indices.contains(0) ? components[0] : 1
                let green = components.indices.contains(1) ? components[1] : red
                let blue = components.indices.contains(2) ? components[2] : red
                let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
                doc.add(.text, start: CGPoint(x: edit.box.rect.minX, y: edit.box.rect.minY),
                        end: CGPoint(x: edit.box.rect.maxX, y: edit.box.rect.maxY),
                        text: edit.text, colorHex: luminance > 0.55 ? "#111111" : "#FFFFFF",
                        thickness: max(2, Double(edit.box.rect.height / 6)))
            }
        }
        objectWillChange.send()
    }

    func deleteSelected() {
        if let id = selectedLayerID {
            snapshot(); imageLayers.removeAll { $0.id == id }; selectedLayerID = nil
        } else if let id = selectedID {
            snapshot(); doc.remove(id: id); selectedID = nil; editingTextID = nil
        }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(Snapshot(doc: doc, base: base, imageLayers: imageLayers))
        doc = prev.doc; base = prev.base; imageLayers = prev.imageLayers
        nextLayerID = (imageLayers.map(\.id).max() ?? 0) + 1
        selectedID = nil; selectedLayerID = nil; editingTextID = nil
        hasUnsavedChanges = true
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(doc: doc, base: base, imageLayers: imageLayers))
        doc = next.doc; base = next.base; imageLayers = next.imageLayers
        nextLayerID = (imageLayers.map(\.id).max() ?? 0) + 1
        selectedID = nil; selectedLayerID = nil; editingTextID = nil
        hasUnsavedChanges = true
    }

    @Published var framed = false { didSet { if framed != oldValue { hasUnsavedChanges = true } } }
    /// Rounded-corner radius in pixels applied on export (0 = square).
    @Published var cornerRadius: Double = 0 { didSet { if cornerRadius != oldValue { hasUnsavedChanges = true } } }

    /// When set, the editor is annotating a video frame — Done bakes this overlay onto the
    /// clip instead of saving an image.
    var onApplyToVideo: ((CGImage) -> Void)?
    var isVideoMode: Bool { onApplyToVideo != nil }

    func flattened() -> CGImage { AnnotationRenderer.flatten(base: compositeBase(), doc: doc) }

    private func compositeBase() -> CGImage {
        guard !imageLayers.isEmpty,
              let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        for layer in imageLayers {
            let target = CGRect(x: layer.rect.minX, y: CGFloat(base.height) - layer.rect.maxY,
                                width: layer.rect.width, height: layer.rect.height)
            context.saveGState(); context.setAlpha(layer.opacity)
            context.draw(layer.image, in: target); context.restoreGState()
        }
        return context.makeImage() ?? base
    }

    /// Annotations and imported image layers on a transparent canvas — for video overlay.
    func overlayImage() -> CGImage {
        guard let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return AnnotationRenderer.flatten(base: base, doc: doc, transparent: true)
        }
        context.clear(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        for layer in imageLayers {
            let target = CGRect(x: layer.rect.minX, y: CGFloat(base.height) - layer.rect.maxY,
                                width: layer.rect.width, height: layer.rect.height)
            context.saveGState(); context.setAlpha(layer.opacity)
            context.draw(layer.image, in: target); context.restoreGState()
        }
        guard let layerCanvas = context.makeImage() else {
            return AnnotationRenderer.flatten(base: base, doc: doc, transparent: true)
        }
        return AnnotationRenderer.flatten(base: layerCanvas, doc: doc)
    }

    /// The image to copy/save — flattened annotations, optionally wrapped in a polished frame.
    func exportImage() -> CGImage {
        let flat = flattened()
        let rounded = cornerRadius > 0 ? (ImageOps.roundedCorners(flat, radius: cornerRadius) ?? flat) : flat
        return framed ? ImagePolish.frame(rounded) : rounded
    }

    /// Write the current (annotated) image back into its library record, refreshing OCR.
    func persistToLibrary() {
        guard let store = appState?.library else { return }
        let flat = exportImage()
        if let id = libraryRecordID {
            store.overwrite(id: id, image: flat)
            let langs = appState?.ocrLanguages ?? ["en-US"]
            Task {
                let text = (try? await OCR.recognize(flat, languages: langs))?.joined(separator: "\n") ?? ""
                if !text.isEmpty { store.setOCRText(id: id, text) }
            }
        } else if let rec = store.saveImage(flat) {
            libraryRecordID = rec.id
        }
        if let id = libraryRecordID {
            if doc.isEmpty && imageLayers.isEmpty && !framed && cornerRadius == 0 {
                store.removeProject(recordID: id)
            } else {
                store.saveProject(recordID: id, project: currentProject(), base: base,
                                  layerImages: Dictionary(uniqueKeysWithValues: imageLayers.map { ($0.id, $0.image) }))
            }
        }
        hasUnsavedChanges = false
    }

    private func currentProject() -> EditorProject {
        EditorProject(doc: doc,
                      layers: imageLayers.map { .init(id: $0.id, rect: $0.rect, opacity: $0.opacity, name: $0.name) },
                      framed: framed, cornerRadius: cornerRadius > 0 ? cornerRadius : nil)
    }

    /// Reopen a saved project: live annotations and layers over the original image.
    func restore(_ loaded: EditorProject.Loaded) {
        base = loaded.base
        doc = loaded.project.doc
        imageLayers = loaded.project.layers.compactMap { layer in
            loaded.layerImages[layer.id].map {
                ImageLayer(id: layer.id, image: $0, rect: layer.rect, opacity: layer.opacity, name: layer.name)
            }
        }
        nextLayerID = (imageLayers.map(\.id).max() ?? 0) + 1
        framed = loaded.project.framed
        cornerRadius = loaded.project.cornerRadius ?? 0
        undoStack.removeAll(); redoStack.removeAll()
        selectedID = nil; selectedLayerID = nil; editingTextID = nil
        hasUnsavedChanges = false
    }

    /// Forget unsaved edits so the window can close without prompting again.
    func discardChanges() { hasUnsavedChanges = false }

    /// Load a brand-new capture into this same editor (reusing one window).
    func reset(base newBase: CGImage, recordID: String?) {
        base = newBase
        libraryRecordID = recordID
        doc = AnnotationDocument()
        imageLayers.removeAll(); selectedLayerID = nil; nextLayerID = 1
        undoStack.removeAll(); redoStack.removeAll()
        selectedID = nil; editingTextID = nil
        framed = false
        cornerRadius = 0
        hasUnsavedChanges = false
    }

    /// OCR the image, find emails / card numbers, and blur them out automatically.
    func autoRedact() {
        let img = base
        let langs = appState?.ocrLanguages ?? ["en-US"]
        Task {
            guard let boxes = try? await OCR.recognizeBoxes(img, languages: langs) else {
                Toast.show("Couldn't scan text", symbol: "exclamationmark.triangle.fill"); return
            }
            let sensitive = boxes.filter {
                Redaction.containsEmail($0.text) || Redaction.containsCardNumber($0.text)
            }
            guard !sensitive.isEmpty else {
                Toast.show("No emails or card numbers found", symbol: "checkmark.shield.fill"); return
            }
            snapshot()
            for b in sensitive {
                let r = b.rect.insetBy(dx: -4, dy: -4)
                doc.add(.blur, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY))
            }
            Toast.show("Redacted \(sensitive.count) item\(sensitive.count == 1 ? "" : "s")", symbol: "eye.slash.fill")
        }
    }
}
