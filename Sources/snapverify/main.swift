import SnapCore
import CoreGraphics
import Foundation
import AppKit

var failures = 0
@MainActor func check(_ cond: Bool, _ msg: String) {
    if cond { print("ok   - \(msg)") } else { failures += 1; print("FAIL - \(msg)") }
}

// MARK: Geometry
let r = selectionRect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 20, y: 10))
check(r == CGRect(x: 20, y: 10, width: 80, height: 70), "selectionRect normalizes reversed drag")

let sel = CaptureSelection(rect: CGRect(x: 0, y: 0, width: 100, height: 50), displayID: 1, scale: 2.0)
check(sel.pixelSize == CGSize(width: 200, height: 100), "pixelSize = points x scale")
check(sel.isValid, "non-empty selection is valid")
check(!CaptureSelection(rect: .zero, displayID: 1, scale: 2).isValid, "zero selection invalid")

// MARK: ImageOps
check(ImageOps.clampBlock(0) == 2, "block size floored to 2")
check(ImageOps.clampBlock(999) == 64, "block size capped at 64")
check(ImageOps.clampBlock(12) == 12, "block size in range unchanged")
check(ImageOps.fit(CGSize(width: 4000, height: 2000), maxEdge: 1000) == CGSize(width: 1000, height: 500),
      "fit scales longest edge to max")
check(ImageOps.fit(CGSize(width: 300, height: 200), maxEdge: 1000) == CGSize(width: 300, height: 200),
      "fit leaves already-small size")

// MARK: Redaction
check(Redaction.containsEmail("ping rahul@iamrraj.com now"), "detects email")
check(!Redaction.containsEmail("no address here"), "no false email")
check(Redaction.containsCardNumber("4242 4242 4242 4242"), "detects Luhn-valid card")
check(!Redaction.containsCardNumber("1234 5678 9012 3456"), "rejects non-Luhn digits")

// MARK: Annotation
var doc = AnnotationDocument()
let s1 = doc.add(.step, start: .zero, end: .zero)
let s2 = doc.add(.step, start: .zero, end: .zero)
check(s1.stepNumber == 1 && s2.stepNumber == 2, "step badges auto-increment")
let a1 = doc.add(.arrow, start: .zero, end: CGPoint(x: 10, y: 10))
check(a1.stepNumber == nil, "non-step has no step number")
doc.remove(id: s1.id)
check(doc.stepCount == 1, "removal is non-destructive to others")
doc.update(id: s2.id) { $0.colorHex = "#00FF00" }
check(doc.items.first(where: { $0.id == s2.id })?.colorHex == "#00FF00", "update mutates in place")

// MARK: OCR (renders text, recognizes it; skips gracefully if Vision unavailable)
func renderText(_ s: String) -> CGImage? {
    let size = NSSize(width: 320, height: 120)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 56),
        .foregroundColor: NSColor.black,
    ]
    (s as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: attrs)
    image.unlockFocus()
    var rect = NSRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

// MARK: Library
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let fixedDate = cal.date(from: DateComponents(year: 2026, month: 7, day: 4,
                                              hour: 14, minute: 30, second: 5))!
check(CaptureLibrary.relativeFolder(for: fixedDate, calendar: cal) == "2026/07",
      "library groups by YYYY/MM")
let stem = CaptureLibrary.stem(for: fixedDate, suffix: "a1b2", calendar: cal)
check(stem.hasPrefix("2026-07-04_") && stem.hasSuffix("_a1b2"), "stem is sortable timestamp (got \(stem))")
let path = CaptureLibrary.relativePath(for: fixedDate, suffix: "a1b2", ext: "png", calendar: cal)
check(path.hasPrefix("2026/07/") && path.hasSuffix(".png"), "relativePath = folder/stem.ext (got \(path))")
let rec = CaptureRecord(id: "x", kind: .image, fileName: path, createdAt: fixedDate,
                        width: 100, height: 50, ocrText: "Invoice total 42.00", title: "Receipt")
check(CaptureLibrary.matches(rec, query: "invoice"), "search finds OCR text")
check(CaptureLibrary.matches(rec, query: "receipt"), "search finds title")
check(!CaptureLibrary.matches(rec, query: "banana"), "search rejects absent term")
check(CaptureLibrary.matches(rec, query: ""), "empty query matches all")

if let img = renderText("HELLO") {
    do {
        let lines = try await OCR.recognize(img)
        let joined = lines.joined(separator: " ").uppercased()
        check(joined.contains("HELLO"), "OCR reads rendered text (got: \(lines))")
    } catch {
        print("skip - OCR unavailable in this environment: \(error)")
    }
} else {
    print("skip - could not render OCR fixture")
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
