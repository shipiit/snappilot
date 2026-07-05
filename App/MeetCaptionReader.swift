import AppKit
import ApplicationServices
import SnapCore

/// Reads Google Meet's on-screen live captions while a meeting records, so the transcript can
/// be labelled with each speaker's real name (Meet shows the name next to every caption line).
///
/// This uses the macOS Accessibility API to read Chrome's caption region — it needs
/// Accessibility permission and Meet's captions (CC) turned on. It's best-effort: if Chrome
/// isn't running, captions are off, or the DOM changes, we simply capture nothing and the
/// meeting falls back to on-device audio transcription (You / Participants).
@MainActor
final class MeetCaptionReader {
    static let shared = MeetCaptionReader()

    private var timer: Timer?
    private var startTime = Date()
    private var committed: [TranscriptLine] = []
    /// Latest growing text per speaker, so we replace an updating caption rather than
    /// appending duplicates, and only "commit" it once it stops growing.
    private var pending: [String: (text: String, start: TimeInterval)] = [:]

    var hasCaptions: Bool { !committed.isEmpty || !pending.isEmpty }

    static func supported() -> Bool {
        AXIsProcessTrusted() && NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.google.Chrome").first != nil
    }

    func start() {
        guard timer == nil else { return }
        startTime = Date(); committed = []; pending = [:]
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    /// Stop reading and return the collected, name-labelled transcript (time-sorted).
    func stop() -> [TranscriptLine] {
        timer?.invalidate(); timer = nil
        for (name, p) in pending { committed.append(TranscriptLine(speaker: name, text: p.text, start: p.start)) }
        pending = [:]
        return committed.sorted { $0.start < $1.start }
    }

    // MARK: Polling

    private func poll() {
        guard let chrome = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return }
        let app = AXUIElementCreateApplication(chrome.processIdentifier)
        guard let captions = findCaptionsContainer(app, depth: 0) else { return }
        var texts: [String] = []
        collectStaticText(captions, into: &texts, depth: 0)
        ingest(pairs(from: texts))
    }

    /// Fold newly-read (name, text) pairs into the pending/committed timeline.
    private func ingest(_ newPairs: [(name: String, text: String)]) {
        let now = Date().timeIntervalSince(startTime)
        for pair in newPairs {
            let name = pair.name
            if let existing = pending[name] {
                if pair.text.hasPrefix(existing.text) || existing.text.hasPrefix(pair.text) {
                    // Same utterance still growing → keep the longer text, same start time.
                    let longer = pair.text.count >= existing.text.count ? pair.text : existing.text
                    pending[name] = (longer, existing.start)
                } else {
                    // A new utterance from this speaker → commit the old one.
                    committed.append(TranscriptLine(speaker: name, text: existing.text, start: existing.start))
                    pending[name] = (pair.text, now)
                }
            } else {
                pending[name] = (pair.text, now)
            }
        }
    }

    /// Turn a flat list of caption static-texts into (speaker, utterance) pairs. Meet renders
    /// a short speaker name followed by the spoken text, so we treat name-like values as the
    /// current speaker and attach following longer values to them.
    private func pairs(from texts: [String]) -> [(name: String, text: String)] {
        var out: [(String, String)] = []
        var currentName = ""
        for raw in texts {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if looksLikeName(value) {
                currentName = value
            } else if !currentName.isEmpty {
                out.append((currentName, value))
            }
        }
        return out
    }

    private func looksLikeName(_ s: String) -> Bool {
        let words = s.split(separator: " ")
        guard words.count <= 3, s.count <= 28 else { return false }
        // Names don't end in sentence punctuation and start uppercase.
        if let last = s.last, ".!?,".contains(last) { return false }
        return s.first?.isUppercase ?? false
    }

    // MARK: Accessibility traversal

    private func findCaptionsContainer(_ el: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 60 else { return nil }
        for attr in ["AXDescription", "AXTitle", "AXLabel"] {
            if let s = axString(el, attr), s.lowercased().contains("caption") { return el }
        }
        for child in axChildren(el) {
            if let found = findCaptionsContainer(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func collectStaticText(_ el: AXUIElement, into out: inout [String], depth: Int) {
        guard depth < 40, out.count < 200 else { return }
        if axString(el, "AXRole") == "AXStaticText",
           let value = axString(el, "AXValue") ?? axString(el, "AXTitle") {
            out.append(value)
        }
        for child in axChildren(el) { collectStaticText(child, into: &out, depth: depth + 1) }
    }

    private func axChildren(_ el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &value)
        return (value as? [AXUIElement]) ?? []
    }

    private func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        return value as? String
    }
}
