import Foundation

/// Line-based text storage, read by rendering, layout and saving without depending on `TextBuffer` itself.
public protocol DocumentSource: Sendable {
    var lineCount: Int { get }
    var isEmpty: Bool { get }
    func line(at index: Int) -> String
    func lines(in range: Range<Int>) -> [String]
    func serializedByteCount(lineEndingSize: Int) -> Int
    func maxLineWidth(in range: Range<Int>, tabSize: Int) -> Int
}

/// A trivial ``DocumentSource`` backed by a plain `[String]`.
public struct ArrayDocumentSource: DocumentSource, Sendable {
    public let storage: [String]

    public init(_ lines: [String]) {
        self.storage = lines.isEmpty ? [""] : lines
    }

    public var lineCount: Int { storage.count }

    public var isEmpty: Bool { lineCount == 1 && storage[0].isEmpty }

    public func line(at index: Int) -> String {
        guard index >= 0, index < storage.count else { return "" }
        return storage[index]
    }

    public func lines(in range: Range<Int>) -> [String] {
        let clamped = range.clamped(to: 0 ..< storage.count)
        return Array(storage[clamped])
    }

    public func serializedByteCount(lineEndingSize: Int) -> Int {
        let lineBytes = storage.reduce(0) { $0 + $1.lengthOfBytes(using: .utf8) }
        return lineBytes + max(0, storage.count - 1) * lineEndingSize
    }

    public func maxLineWidth(in range: Range<Int>, tabSize: Int) -> Int {
        let clamped = range.clamped(to: 0 ..< storage.count)
        var maxWidth = 0
        for lineIndex in clamped {
            maxWidth = max(
                maxWidth, TextDisplayMetrics.displayWidth(of: storage[lineIndex], tabSize: tabSize))
        }
        return maxWidth
    }
}
