import SwiftUI

/// A lightweight Markdown renderer for ticket descriptions — headings, bullet & numbered
/// lists, checkboxes, block quotes, code blocks, dividers, and inline formatting (bold,
/// italic, `code`, links). Not a full CommonMark engine, but covers what people actually
/// type in an issue tracker.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    private enum Block: Equatable {
        case heading(Int, String)
        case bullet(String)
        case numbered(Int, String)
        case checkbox(Bool, String)
        case quote(String)
        case code(String)
        case image(String, String)   // alt, url
        case divider
        case paragraph(String)
        case blank
    }

    private func blocks() -> [Block] {
        var result: [Block] = []
        var codeLines: [String] = []
        var inCode = false
        var number = 1

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode { result.append(.code(codeLines.joined(separator: "\n"))); codeLines = [] }
                inCode.toggle()
                continue
            }
            if inCode { codeLines.append(line); continue }

            if trimmed.isEmpty { result.append(.blank); number = 1; continue }
            if trimmed == "---" || trimmed == "***" { result.append(.divider); continue }

            if let img = imageLine(trimmed) { result.append(.image(img.0, img.1)); continue }
            if let h = heading(trimmed) { result.append(.heading(h.0, h.1)); continue }
            if trimmed.hasPrefix("- [ ] ") { result.append(.checkbox(false, String(trimmed.dropFirst(6)))); continue }
            if trimmed.lowercased().hasPrefix("- [x] ") { result.append(.checkbox(true, String(trimmed.dropFirst(6)))); continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { result.append(.bullet(String(trimmed.dropFirst(2)))); continue }
            if let num = numbered(trimmed) { result.append(.numbered(number, num)); number += 1; continue }
            if trimmed.hasPrefix("> ") { result.append(.quote(String(trimmed.dropFirst(2)))); continue }

            result.append(.paragraph(trimmed))
            number = 1
        }
        if inCode, !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
        return result
    }

    private func heading(_ s: String) -> (Int, String)? {
        for level in [3, 2, 1] {
            let prefix = String(repeating: "#", count: level) + " "
            if s.hasPrefix(prefix) { return (level, String(s.dropFirst(prefix.count))) }
        }
        return nil
    }

    /// Parse a line that is exactly an image: `![alt](url)`.
    private func imageLine(_ s: String) -> (String, String)? {
        guard s.hasPrefix("!["), let bracket = s.range(of: "]("), s.hasSuffix(")") else { return nil }
        let alt = String(s[s.index(s.startIndex, offsetBy: 2)..<bracket.lowerBound])
        let url = String(s[bracket.upperBound..<s.index(before: s.endIndex)])
        return url.isEmpty ? nil : (alt, url)
    }

    private func numbered(_ s: String) -> String? {
        guard let dot = s.firstIndex(of: "."), s.startIndex < dot else { return nil }
        let head = s[s.startIndex..<dot]
        guard !head.isEmpty, head.allSatisfy({ $0.isNumber }), s.index(after: dot) < s.endIndex,
              s[s.index(after: dot)] == " " else { return nil }
        return String(s[s.index(dot, offsetBy: 2)...])
    }

    @ViewBuilder private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let t):
            inline(t).font(.system(size: level == 1 ? 20 : level == 2 ? 16 : 14, weight: .bold))
                .padding(.top, 4)
        case .bullet(let t):
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(.secondary).frame(width: 5, height: 5).padding(.top, 7)
                inline(t)
            }
        case .numbered(let n, let t):
            HStack(alignment: .top, spacing: 8) {
                Text("\(n).").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                inline(t)
            }
        case .checkbox(let done, let t):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.accentColor : .secondary)
                inline(t).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            }
        case .quote(let t):
            HStack(spacing: 8) {
                Rectangle().fill(.secondary).frame(width: 3)
                inline(t).foregroundStyle(.secondary)
            }
        case .code(let t):
            Text(t).font(.system(.callout, design: .monospaced))
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 8))
        case .image(let alt, let urlString):
            if let img = loadImage(urlString) {
                VStack(alignment: .leading, spacing: 3) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if !alt.isEmpty { Text(alt).font(.caption2).foregroundStyle(.secondary) }
                }
            } else {
                Label(alt.isEmpty ? "Image" : alt, systemImage: "photo").font(.callout).foregroundStyle(.secondary)
            }
        case .divider:
            Divider().padding(.vertical, 2)
        case .paragraph(let t):
            inline(t)
        case .blank:
            Spacer().frame(height: 2)
        }
    }

    /// Load an image referenced by a Markdown image URL (file path, file:// URL, or a
    /// bare absolute path). Remote http(s) images are not fetched inline.
    private func loadImage(_ urlString: String) -> NSImage? {
        if urlString.hasPrefix("http") { return nil }
        if let url = URL(string: urlString), url.isFileURL, let img = NSImage(contentsOf: url) { return img }
        return NSImage(contentsOfFile: urlString)
    }

    /// Inline formatting via AttributedString markdown (bold, italic, code, links).
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }
}
