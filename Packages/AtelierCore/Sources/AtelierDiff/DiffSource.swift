import AemiKernel
import Foundation

/// Lines a diff runs over. A source addresses its lines by index and lends their bytes, so a rope, a mapped file
/// or a list of substrings is diffed without making strings: identity comes from hashing the normalised bytes and
/// equal hashes are confirmed byte by byte.
public protocol DiffSource {
    var lineCount: Int { get }
    /// Lends the bytes of line `index`, without its terminator.
    func withLineBytes<R>(at index: Int, _ body: (Span<UInt8>) throws -> R) rethrows -> R
}

extension DiffSource {
    /// Leading whitespace width of line `index`, tabs to the next multiple of eight; nil for a blank line.
    public func indent(at index: Int) -> Int? {
        withLineBytes(at: index) { LineDiff.indent(of: $0) }
    }
}

/// Lines held as substrings of one string, as the text kit side of a diff produces them.
public struct SubstringLines: DiffSource {
    public let lines: [Substring]

    public init(_ lines: [Substring]) {
        self.lines = lines
    }

    public var lineCount: Int { lines.count }

    public func withLineBytes<R>(at index: Int, _ body: (Span<UInt8>) throws -> R) rethrows -> R {
        let line = lines[index]
        if let result = try line.utf8.withContiguousStorageIfAvailable({ buffer in
            try body(unsafe Span(_unsafeElements: buffer))
        }) {
            return result
        }
        // A non-contiguous substring, which native strings never are: copy this one line.
        let bytes = Array(line.utf8)
        return try body(bytes.span)
    }
}

/// Lines held as byte arrays, one per line, without terminators.
public struct ByteLines: DiffSource {
    public let lines: [[UInt8]]

    public init(_ lines: [[UInt8]]) {
        self.lines = lines
    }

    public var lineCount: Int { lines.count }

    public func withLineBytes<R>(at index: Int, _ body: (Span<UInt8>) throws -> R) rethrows -> R {
        let line = lines[index]
        return try body(line.span)
    }
}

/// Gives every distinct line one small integer, across both sides of a diff, under a whitespace mode.
///
/// Identity is the XXH64 of the normalised bytes; the normalised bytes of every distinct line are kept in one
/// arena, so a hash already seen is confirmed by one comparison against the arena and a collision can only cost
/// that comparison, never a wrong match.
struct LineInterner {
    let whitespace: WhitespaceMode
    /// The identifier first registered under a hash.
    private var firstIdentifier: [UInt64: Int] = [:]
    /// Further identifiers under a hash, for the rare collision.
    private var collisions: [UInt64: [Int]] = [:]
    /// The normalised bytes of every identifier, back to back, and where each one lies.
    private var arena: [UInt8] = []
    private var ranges: [Range<Int>] = []

    init(whitespace: WhitespaceMode) {
        self.whitespace = whitespace
    }

    /// One identifier per line of `source`, and each line's indent measured in the same pass; a later source's
    /// lines match an earlier source's.
    /// - Complexity: O(bytes of the source), plus one comparison per repeated line.
    mutating func intern(_ source: some DiffSource) -> (identifiers: [Int], indents: [Int?]) {
        var identifiers: [Int] = []
        var indents: [Int?] = []
        identifiers.reserveCapacity(source.lineCount)
        indents.reserveCapacity(source.lineCount)
        firstIdentifier.reserveCapacity(firstIdentifier.count + source.lineCount)
        var scratch: [UInt8] = []
        for line in 0 ..< source.lineCount {
            let (identifier, indent) = source.withLineBytes(at: line) { bytes in
                (
                    whitespace.withNormalized(bytes, scratch: &scratch) { normalized in identify(normalized) },
                    LineDiff.indent(of: bytes)
                )
            }
            identifiers.append(identifier)
            indents.append(indent)
        }
        return (identifiers, indents)
    }

    /// The identifier of `normalized`, registering it when it is new.
    private mutating func identify(_ normalized: UnsafeRawBufferPointer) -> Int {
        let hash = XXH64.hash(normalized)
        if let first = firstIdentifier[hash] {
            if matches(first, normalized) { return first }
            for candidate in collisions[hash] ?? [] where matches(candidate, normalized) {
                return candidate
            }
            let identifier = register(normalized)
            collisions[hash, default: []].append(identifier)
            return identifier
        }
        let identifier = register(normalized)
        firstIdentifier[hash] = identifier
        return identifier
    }

    private mutating func register(_ normalized: UnsafeRawBufferPointer) -> Int {
        let start = arena.count
        arena.append(contentsOf: normalized)
        ranges.append(start ..< arena.count)
        return ranges.count - 1
    }

    private func matches(_ identifier: Int, _ normalized: UnsafeRawBufferPointer) -> Bool {
        let range = ranges[identifier]
        guard range.count == normalized.count else { return false }
        return arena.withUnsafeBytes {
            unsafe memcmp($0.baseAddress! + range.lowerBound, normalized.baseAddress, range.count) == 0
        }
    }
}

extension WhitespaceMode {
    /// Calls `body` with the bytes of `line` that take part in comparison under this mode: a sub-range of the
    /// line for the trimming modes, a filtered copy in `scratch` when inner whitespace is ignored.
    /// - Complexity: O(line)
    func withNormalized<R>(_ line: Span<UInt8>, scratch: inout [UInt8], _ body: (UnsafeRawBufferPointer) -> R) -> R {
        var start = 0
        var end = line.count
        switch self {
            case .exact:
                break
            case .ignoreTrailing:
                while end > 0, Self.isSpace(line[end - 1]) { end -= 1 }
            case .ignoreLeadingAndTrailing:
                while start < end, Self.isSpace(line[start]) { start += 1 }
                while end > start, Self.isSpace(line[end - 1]) { end -= 1 }
            case .ignoreAll:
                scratch.removeAll(keepingCapacity: true)
                scratch.reserveCapacity(line.count)
                for index in 0 ..< line.count where !Self.isSpace(line[index]) {
                    scratch.append(line[index])
                }
                return scratch.withUnsafeBytes(body)
        }
        return line.withUnsafeBufferPointer { buffer in
            body(UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: buffer[start ..< end])))
        }
    }
}
