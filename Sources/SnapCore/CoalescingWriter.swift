import Foundation

/// Writes files off the main thread and coalesces bursts: every `schedule` for the same URL
/// within `delay` collapses into one write of the latest value. The library index is several
/// megabytes and used to be rewritten synchronously on every favorite, tag and OCR update.
public final class CoalescingWriter: @unchecked Sendable {
    public typealias Encode = @Sendable () throws -> Data

    private let queue = DispatchQueue(label: "ai.snappilot.coalescing-writer", qos: .utility)
    private let delay: TimeInterval
    private let onError: @Sendable (URL, Error) -> Void
    private var pending: [URL: Encode] = [:]
    private var writes = 0

    public init(delay: TimeInterval = 0.5, onError: @escaping @Sendable (URL, Error) -> Void) {
        self.delay = delay
        self.onError = onError
    }

    /// Queue a write. `encode` runs on the writer's queue, so pass it a value snapshot.
    public func schedule(_ url: URL, encode: @escaping Encode) {
        queue.async {
            let isFirst = self.pending.updateValue(encode, forKey: url) == nil
            guard isFirst else { return }
            self.queue.asyncAfter(deadline: .now() + self.delay) { self.write(url) }
        }
    }

    /// Write everything pending right now and wait for it — call before the app quits.
    public func flush() {
        queue.sync { for url in Array(pending.keys) { write(url) } }
    }

    /// Completed writes so far (for verification).
    public var writeCount: Int { queue.sync { writes } }

    private func write(_ url: URL) {
        guard let encode = pending.removeValue(forKey: url) else { return }
        do {
            try encode().write(to: url, options: .atomic)
            writes += 1
        } catch {
            onError(url, error)
        }
    }
}
