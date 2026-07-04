import Foundation

/// Detects sensitive strings so the editor can offer one-click auto-redaction.
public enum Redaction {
    public static func containsEmail(_ text: String) -> Bool {
        text.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Detects a 13–16 digit sequence (optionally space/dash separated) passing Luhn.
    public static func containsCardNumber(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,16}\b"#) else {
            return false
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let digits = ns.substring(with: m.range).filter(\.isNumber)
            if (13...16).contains(digits.count) && luhn(digits) { return true }
        }
        return false
    }

    static func luhn(_ s: String) -> Bool {
        var sum = 0
        var alt = false
        for ch in s.reversed() {
            guard var d = ch.wholeNumberValue else { return false }
            if alt { d *= 2; if d > 9 { d -= 9 } }
            sum += d
            alt.toggle()
        }
        return sum % 10 == 0
    }
}
