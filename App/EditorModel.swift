import SwiftUI
import CoreGraphics
import SnapCore

/// Editor state for one capture: the base image, annotation document, current tool,
/// and undo/redo. Coordinates are in the base image's pixel space (top-left origin).
@MainActor
final class EditorModel: ObservableObject {
    @Published var base: CGImage
    weak var appState: AppState?
    /// The library record this capture belongs to (saved instantly on capture).
    var libraryRecordID: String?

    @Published var doc = AnnotationDocument()
    @Published var tool: Tool = .arrow
    @Published var colorHex = "#FF3B30"
    @Published var thickness: Double = 4
    @Published var filled = false
    @Published var opacity: Double = 1
    @Published var stepStyle: StepStyle = .number
    @Published var lineStyle: LineStyle = .solid
    @Published var startHead: ArrowHead = .none
    @Published var endHead: ArrowHead = .arrow
    @Published var arrowSize: ArrowSize = .medium
    @Published var stamp = "⭐️"
    @Published var selectedID: Int?
    @Published var editingTextID: Int?

    /// A restorable editor state — both the layers and the base image (crop changes base).
    private struct Snapshot { var doc: AnnotationDocument; var base: CGImage }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(base: CGImage, appState: AppState?) {
        self.base = base
        self.appState = appState
    }

    var pixelSize: CGSize { CGSize(width: base.width, height: base.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() {
        undoStack.append(Snapshot(doc: doc, base: base))
        redoStack.removeAll()
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
        selectedID = nil
    }

    func updateText(id: Int, _ text: String) {
        doc.update(id: id) { $0.text = text }
        objectWillChange.send()
    }

    func move(id: Int, dx: CGFloat, dy: CGFloat) {
        doc.update(id: id) {
            $0.start.x += dx; $0.start.y += dy
            $0.end.x += dx; $0.end.y += dy
        }
        objectWillChange.send()
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        snapshot(); doc.remove(id: id); selectedID = nil; editingTextID = nil
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(Snapshot(doc: doc, base: base))
        doc = prev.doc; base = prev.base
        selectedID = nil; editingTextID = nil
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(doc: doc, base: base))
        doc = next.doc; base = next.base
        selectedID = nil; editingTextID = nil
    }

    @Published var framed = false

    func flattened() -> CGImage { AnnotationRenderer.flatten(base: base, doc: doc) }

    /// The image to copy/save — flattened annotations, optionally wrapped in a polished frame.
    func exportImage() -> CGImage {
        let flat = flattened()
        return framed ? ImagePolish.frame(flat) : flat
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
    }

    /// Load a brand-new capture into this same editor (reusing one window).
    func reset(base newBase: CGImage, recordID: String?) {
        base = newBase
        libraryRecordID = recordID
        doc = AnnotationDocument()
        undoStack.removeAll(); redoStack.removeAll()
        selectedID = nil; editingTextID = nil
        framed = false
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
