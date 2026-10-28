import AppKit
import SnapCore

/// Editor actions beyond drawing: object copy/cut/paste, nudging, saved styles and canvas growth.
extension EditorModel {
    private enum Clip {
        case annotation(Annotation)
        case layer(ImageLayer)
    }
    /// Shared across editor windows so objects can be copied from one capture to another.
    @MainActor private static var clip: Clip?
    @MainActor private static var pasteCount = 0
    /// System pasteboard change count right after our copy — anything copied later wins.
    @MainActor private static var clipChangeCount = -1

    var hasSelection: Bool { selectedID != nil || selectedLayerID != nil }

    /// Copy the selected object. Returns false when nothing is selected.
    @discardableResult
    func copySelection() -> Bool {
        if let id = selectedLayerID, let layer = imageLayers.first(where: { $0.id == id }) {
            Self.clip = .layer(layer)
        } else if let id = selectedID, let annotation = doc.items.first(where: { $0.id == id }) {
            Self.clip = .annotation(annotation)
        } else {
            return false
        }
        Self.pasteCount = 0
        // Also put a plain image on the system pasteboard so other apps can paste it.
        if case .layer(let layer) = Self.clip { Exporter.copyToPasteboard(layer.image) }
        Self.clipChangeCount = NSPasteboard.general.changeCount
        return true
    }

    @discardableResult
    func cutSelection() -> Bool {
        guard copySelection() else { return false }
        deleteSelected()
        return true
    }

    /// Paste the copied object (each paste steps further down-right), or an image from the
    /// system pasteboard as a new layer. Returns false when there is nothing to paste.
    @discardableResult
    func paste() -> Bool {
        let pasteboard = NSPasteboard.general
        let copiedElsewhere = Self.clip == nil || pasteboard.changeCount != Self.clipChangeCount
        if copiedElsewhere,
           let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            addImageLayer(cgImage)
            return true
        }
        guard let clip = Self.clip else { return false }
        Self.pasteCount += 1
        let shift = CGFloat(16 * Self.pasteCount)
        switch clip {
        case .annotation(let annotation):
            beginTransform()
            selectedID = doc.insertCopy(of: annotation, offset: CGPoint(x: shift, y: shift)).id
            selectedLayerID = nil
        case .layer(let layer):
            addImageLayer(layer.image, centeredAt: CGPoint(x: layer.rect.midX + shift, y: layer.rect.midY + shift))
        }
        return true
    }

    /// Move the selection by a few pixels (arrow keys; Shift moves 10).
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard hasSelection else { return }
        beginTransform()
        if let id = selectedLayerID { moveLayer(id: id, dx: dx, dy: dy) }
        else if let id = selectedID { move(id: id, dx: dx, dy: dy) }
    }

    // MARK: Styles

    /// Load a saved style into the panel (which also restyles any selection).
    func applyStyle(_ style: AnnotationStyle) {
        colorHex = style.colorHex; thickness = style.thickness; filled = style.filled; opacity = style.opacity
        stepStyle = style.stepStyle; lineStyle = style.lineStyle
        startHead = style.startHead; endHead = style.endHead; arrowSize = style.arrowSize
    }

    func count(of tool: Tool) -> Int { doc.items.filter { $0.tool == tool }.count }

    func applyCurrentStyleToAll(of tool: Tool) {
        var preview = doc
        guard preview.restyleAll(of: tool, to: currentStyle) > 0 else { return }
        beginTransform()
        let changed = doc.restyleAll(of: tool, to: currentStyle)
        Toast.show("Restyled \(changed) \(changed == 1 ? "annotation" : "annotations")", symbol: "paintbrush.fill")
    }

    // MARK: Canvas

    /// Grow the canvas (transparent) so every layer and annotation fits. Returns false when
    /// everything already fits.
    @discardableResult
    func expandCanvasToFit(padding: CGFloat = 0, recordUndo: Bool = true) -> Bool {
        let rects = imageLayers.map(\.rect) + doc.items.map { selectionRect(from: $0.start, to: $0.end) }
        guard let growth = LayerPlacement.expansion(canvas: pixelSize, fitting: rects, padding: padding),
              let grown = ImageOps.expanded(base, to: growth.size, offset: growth.offset) else { return false }
        if recordUndo { beginTransform() }
        base = grown
        doc.translateAll(dx: growth.offset.dx, dy: growth.offset.dy)
        for index in imageLayers.indices {
            imageLayers[index].rect = imageLayers[index].rect.offsetBy(dx: growth.offset.dx, dy: growth.offset.dy)
        }
        return true
    }

    /// Combine an image beside the current one at full size, growing the canvas to hold both.
    func addImageBeside(_ image: CGImage) {
        let size = CGSize(width: image.width, height: image.height)
        let rect = LayerPlacement.besideRect(size: size, canvas: pixelSize, gap: 16)
        addImageLayer(image, centeredAt: CGPoint(x: rect.midX, y: rect.midY), clampToCanvas: false)
        expandCanvasToFit(recordUndo: false)   // one undo step for the whole combine
    }

    // MARK: Saving choices (issue #1)

    /// Keep the original capture untouched and add this edit to the library as a new one.
    func saveAsNewCapture() {
        libraryRecordID = nil
        persistToLibrary()
        Toast.show("Saved as a new capture", symbol: "plus.square.on.square")
    }

    /// Whether "Save to Original File" can write back in the file's own format.
    var canSaveToOriginal: Bool {
        externalSourceURL.flatMap { CaptureFormat(fileExtension: $0.pathExtension) } != nil
    }

    /// Overwrite the file this image was opened from, in its own format.
    func saveToOriginalFile() {
        guard let url = externalSourceURL, let format = CaptureFormat(fileExtension: url.pathExtension) else { return }
        let quality = appState?.captureQuality ?? CaptureEncoder.defaultQuality
        if CaptureEncoder.write(exportImage(), format: format, quality: quality, to: url) {
            discardChanges()
            Toast.show("Saved to \(url.lastPathComponent)", symbol: "checkmark.circle.fill")
        } else {
            Toast.show("Couldn't save \(url.lastPathComponent)", symbol: "exclamationmark.triangle.fill")
        }
    }
}
