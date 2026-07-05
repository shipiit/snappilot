import CoreGraphics
import Foundation

/// Stitches a sequence of overlapping screenshots (taken while scrolling a view downward)
/// into one tall image. It works out how far the content scrolled between two frames by
/// matching the bottom rows of the previous frame against the top rows of the next one,
/// then appends only the newly-revealed rows. Pure CoreGraphics so it can be unit-tested.
public enum ScrollStitcher {

    /// Combine frames (top-to-bottom scroll order) into a single tall image.
    public static func stitch(_ frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let sigs = frames.map { rowSignatures($0) }

        // Each piece: which source frame, first source row to copy, and how many rows.
        var pieces: [(img: CGImage, srcTop: Int, rows: Int)] = [(first, 0, first.height)]
        var totalHeight = first.height

        for i in 1..<frames.count {
            let f = frames[i]
            guard f.width == width else { continue }
            let overlap = bestOverlap(prev: sigs[i - 1], next: sigs[i])
            let newRows = f.height - overlap
            guard newRows > 0 else { continue }       // no new content → skip (e.g. hit bottom)
            pieces.append((f, overlap, newRows))
            totalHeight += newRows
        }

        guard let ctx = CGContext(data: nil, width: width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var yTop = 0
        for p in pieces {
            guard let cropped = p.img.cropping(to: CGRect(x: 0, y: p.srcTop, width: width, height: p.rows)) else { continue }
            let destY = totalHeight - yTop - p.rows      // CG origin is bottom-left
            ctx.draw(cropped, in: CGRect(x: 0, y: destY, width: width, height: p.rows))
            yTop += p.rows
        }
        return ctx.makeImage()
    }

    /// How many of `prev`'s bottom rows line up with `next`'s top rows (0 = no overlap found).
    public static func bestOverlap(prev: [[UInt8]], next: [[UInt8]]) -> Int {
        let h = min(prev.count, next.count)
        guard h > 8 else { return 0 }
        let minOv = max(4, h / 12)
        var best = 0
        var bestDiff = Double.greatestFiniteMagnitude
        for ov in stride(from: h - 1, through: minOv, by: -1) {
            let step = max(1, ov / 48)
            var diff = 0.0, n = 0.0
            var i = 0
            while i < ov {
                diff += rowDiff(prev[prev.count - ov + i], next[i]); n += 1
                i += step
            }
            let avg = diff / max(1, n)
            if avg < bestDiff { bestDiff = avg; best = ov }
        }
        return bestDiff < 20.0 ? best : 0     // avg per-sample 8-bit difference threshold
    }

    /// Downsample every row to a small grayscale signature (top-to-bottom order).
    public static func rowSignatures(_ image: CGImage, sigWidth: Int = 24) -> [[UInt8]] {
        let h = image.height
        guard h > 0, let ctx = CGContext(data: nil, width: sigWidth, height: h,
                                         bitsPerComponent: 8, bytesPerRow: sigWidth,
                                         space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sigWidth, height: h))
        guard let data = ctx.data else { return [] }
        let ptr = data.bindMemory(to: UInt8.self, capacity: sigWidth * h)
        var rows: [[UInt8]] = []
        rows.reserveCapacity(h)
        for topRow in 0..<h {                            // buffer row 0 is the top row
            let base = topRow * sigWidth
            rows.append(Array(UnsafeBufferPointer(start: ptr + base, count: sigWidth)))
        }
        return rows
    }

    private static func rowDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 255 }
        var sum = 0
        for i in 0..<n { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(n)
    }
}
