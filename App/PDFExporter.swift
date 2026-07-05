import PDFKit
import AppKit

/// Combines image captures into a single multi-page PDF.
enum PDFExporter {
    /// Each image URL becomes one page. Returns true on success.
    static func export(imageURLs: [URL], to dest: URL) -> Bool {
        let doc = PDFDocument()
        var page = 0
        for url in imageURLs {
            guard let img = NSImage(contentsOf: url), let pdfPage = PDFPage(image: img) else { continue }
            doc.insert(pdfPage, at: page)
            page += 1
        }
        guard page > 0 else { return false }
        return doc.write(to: dest)
    }
}
