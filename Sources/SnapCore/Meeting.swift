import Foundation

/// One attributed line of a meeting transcript: who spoke, what they said, and when
/// (seconds from the start of the recording).
public struct TranscriptLine: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(speaker)-\(Int(start * 1000))-\(text.prefix(12))" }
    public var speaker: String
    public var text: String
    public var start: TimeInterval

    public init(speaker: String, text: String, start: TimeInterval) {
        self.speaker = speaker; self.text = text; self.start = start
    }

    /// mm:ss timestamp for display.
    public var stamp: String {
        let s = Int(start.rounded()); return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// The AI-derived outcome of a meeting: a short summary, action items, and key points.
public struct MeetingNotes: Codable, Equatable, Sendable {
    public struct Task: Codable, Equatable, Sendable, Identifiable {
        public var id: String { "\(owner)-\(text.prefix(20))" }
        public var text: String
        public var owner: String        // "You", "Participants", or a name
        public init(text: String, owner: String) { self.text = text; self.owner = owner }
    }
    public var summary: [String]
    public var tasks: [Task]
    public var keyPoints: [String]
    public init(summary: [String] = [], tasks: [Task] = [], keyPoints: [String] = []) {
        self.summary = summary; self.tasks = tasks; self.keyPoints = keyPoints
    }
    public var isEmpty: Bool { summary.isEmpty && tasks.isEmpty && keyPoints.isEmpty }
}

/// Turns a transcript into notes entirely on-device with deterministic heuristics — no
/// model download, no network. It reads the whole conversation, splits it into sentences,
/// and pulls out anything that sounds like a commitment ("I'll…", "let's…", "we need to…")
/// or a decision ("we agreed…", "the deadline is…").
public enum MeetingAnalyzer {

    // Phrases that signal an action item / task.
    private static let taskCues = [
        "i'll", "i will", "i'm going to", "i am going to", "i can ", "let me ",
        "we'll", "we will", "we need to", "we have to", "we should",
        "let's", "let us", "need to", "needs to", "have to ", "has to ",
        "should ", "must ", "action item", "follow up", "follow-up", "to do", "todo",
        "assign", "make sure", "please ", "can you", "could you", "will you",
        "going to send", "going to share", "i'll take", "take care of", "own the",
        "by tomorrow", "by monday", "by tuesday", "by wednesday", "by thursday",
        "by friday", "by end of", "by eod", "next step", "next steps", "circle back",
    ]

    // Phrases that signal a decision / key point.
    private static let keyCues = [
        "decided", "we agreed", "agreed", "the plan is", "plan is to", "conclusion",
        "deadline", "due date", "launch", "ship", "release", "important", "key point",
        "the goal", "our goal", "priority", "blocker", "blocked", "risk", "budget",
        "target", "milestone", "in summary", "to summarize", "bottom line", "the issue is",
    ]

    public static func analyze(_ lines: [TranscriptLine]) -> MeetingNotes {
        // Flatten to sentences, remembering the speaker of each.
        var sentences: [(text: String, speaker: String, order: Int)] = []
        var order = 0
        for line in lines {
            for raw in splitSentences(line.text) {
                let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard s.split(separator: " ").count >= 3 else { continue }   // skip fragments
                sentences.append((s, line.speaker, order)); order += 1
            }
        }

        var tasks: [MeetingNotes.Task] = []
        var keyPoints: [String] = []
        var seenTask = Set<String>(), seenKey = Set<String>()
        var scored: [(text: String, score: Int, order: Int)] = []

        for item in sentences {
            let low = item.text.lowercased()
            let isTask = taskCues.contains { low.contains($0) }
            let isKey = keyCues.contains { low.contains($0) }
            let hasDigit = item.text.contains { $0.isNumber }

            if isTask {
                let norm = normalize(item.text)
                if seenTask.insert(norm).inserted {
                    tasks.append(.init(text: clean(item.text), owner: ownerFor(low, speaker: item.speaker)))
                }
            }
            if isKey {
                let norm = normalize(item.text)
                if seenKey.insert(norm).inserted { keyPoints.append(clean(item.text)) }
            }

            var score = 0
            if isTask { score += 2 }
            if isKey { score += 2 }
            if hasDigit { score += 1 }
            let words = item.text.split(separator: " ").count
            if words >= 6 && words <= 32 { score += 1 }
            if score > 0 { scored.append((clean(item.text), score, item.order)) }
        }

        // Summary: highest-signal sentences, presented in the order they were said.
        let summary = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .prefix(6)
            .sorted { $0.order < $1.order }
            .map { $0.text }
            .reduce(into: [String]()) { acc, t in if !acc.contains(t) { acc.append(t) } }

        return MeetingNotes(summary: Array(summary.prefix(5)),
                            tasks: Array(tasks.prefix(30)),
                            keyPoints: Array(keyPoints.prefix(20)))
    }

    /// Best guess at who owns a task from its wording.
    private static func ownerFor(_ low: String, speaker: String) -> String {
        if low.contains("i'll") || low.contains("i will") || low.contains("i'm going to")
            || low.contains("i am going to") || low.contains("let me") || low.contains("i'll take") {
            return speaker
        }
        // "can you / could you / please / you should" delegates to the other side.
        if low.contains("can you") || low.contains("could you") || low.contains("will you")
            || low.contains("you should") || low.contains("please ") {
            return speaker == "You" ? "Participants" : "You"
        }
        return speaker
    }

    /// Split a block of text into sentences on ., !, ? — tolerant of missing punctuation
    /// (speech transcripts often run on, so also break on long clauses is avoided here to
    /// keep it simple/deterministic).
    public static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                out.append(cur); cur = ""
            }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = t.first, first.isLowercase { t = first.uppercased() + t.dropFirst() }
        return t
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }
}
