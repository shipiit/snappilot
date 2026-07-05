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

// Region crop math: bottom-left points → top-left pixels.
// rect (20,30,100,50) on a 900pt-tall retina (2x) screen: maxY=80 → topY=820 → ×2.
let crop = pixelCropRect(selection: CGRect(x: 20, y: 30, width: 100, height: 50),
                         screenHeightPoints: 900, scale: 2)
check(crop == CGRect(x: 40, y: 1640, width: 200, height: 100),
      "pixelCropRect flips Y and scales (got \(crop))")
// A selection at the very top of the screen maps to y=0 in pixels.
let topCrop = pixelCropRect(selection: CGRect(x: 0, y: 850, width: 100, height: 50),
                            screenHeightPoints: 900, scale: 2)
check(topCrop.minY == 0, "selection at screen top crops from pixel y=0 (got \(topCrop.minY))")
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

// Step numbering styles
check(StepStyle.number.label(for: 3) == "3", "numeric step label")
check(StepStyle.upper.label(for: 1) == "A", "upper letter A")
check(StepStyle.upper.label(for: 26) == "Z", "upper letter Z")
check(StepStyle.upper.label(for: 27) == "AA", "upper letter wraps to AA")
check(StepStyle.lower.label(for: 2) == "b", "lower letter b")

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

// MARK: Meeting analysis
let meetingLines = [
    TranscriptLine(speaker: "You", text: "Thanks everyone for joining. Let's ship the release on Friday.", start: 1),
    TranscriptLine(speaker: "Participants", text: "Sounds good. I'll handle the QA testing before then.", start: 5),
    TranscriptLine(speaker: "Participants", text: "We agreed the deadline is Friday at 5pm.", start: 9),
    TranscriptLine(speaker: "You", text: "Can you also write the release notes?", start: 13),
    TranscriptLine(speaker: "Participants", text: "Yeah.", start: 16),   // fragment, should be dropped
]
let notes = MeetingAnalyzer.analyze(meetingLines)
check(notes.tasks.contains { $0.text.lowercased().contains("qa testing") },
      "extracts 'I'll handle QA' as a task")
check(notes.tasks.contains { $0.owner == "Participants" && $0.text.lowercased().contains("qa") },
      "owner of 'I'll handle QA' is the speaker (Participants)")
check(notes.tasks.contains { $0.text.lowercased().contains("release notes") && $0.owner == "Participants" },
      "'can you write release notes' delegates to Participants")
check(notes.keyPoints.contains { $0.lowercased().contains("deadline is friday") },
      "extracts the deadline as a key point")
check(!notes.summary.isEmpty, "summary is non-empty")
check(!notes.tasks.contains { $0.text.lowercased() == "yeah." },
      "one-word fragments are not tasks")
check(MeetingAnalyzer.splitSentences("One. Two! Three?").count == 3, "splits three sentences")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
