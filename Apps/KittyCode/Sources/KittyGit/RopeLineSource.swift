import AtelierDiff
public import AtelierText
import Foundation

/// A snapshot read in bounded line chunks, so diffing avoids one rope descent per line.
struct RopeLineSource: DiffSource {
    static let chunkSize = 4_096

    let lineCount: Int
    private let chunks: [[String]]

    init?(rope: Rope) {
        lineCount = rope.lineCount
        var lines: [[String]] = []
        lines.reserveCapacity((lineCount + Self.chunkSize - 1) / Self.chunkSize)
        for start in stride(from: 0, to: lineCount, by: Self.chunkSize) {
            guard !Task.isCancelled else { return nil }
            lines.append(rope.lines(in: start ..< min(start + Self.chunkSize, lineCount)))
        }
        chunks = lines
    }

    func withLineBytes<R>(at index: Int, _ body: (Span<UInt8>) throws -> R) rethrows -> R {
        let line = chunks[index / Self.chunkSize][index % Self.chunkSize]
        return try body(line.utf8Span.span)
    }

    func line(at index: Int) -> Substring {
        Substring(chunks[index / Self.chunkSize][index % Self.chunkSize])
    }
}

/// A decoration provider that accepts an immutable rope snapshot.
public protocol RopeGitLineDecorationProvider: GitLineDecorationProvider {
    func lineDecorations(for path: String, rope: Rope) async -> GitLineDecorations
}
