import Foundation

/// A text buffer backed by a gap buffer of lines for O(1) amortized insert/delete at the cursor.
///
/// The gap buffer maintains a contiguous storage with a gap (unused region)
/// that moves to the edit point. This makes sequential inserts and deletes
/// near the cursor O(1) amortized, compared to O(n) for a plain array.
public struct TextBuffer: Sendable {
    /// Internal gap buffer storage for lines.
    private var storage: ContiguousArray<String>
    /// Start index of the gap in storage.
    private var gapStart: Int
    /// Length of the gap (number of unused slots).
    private var gapLength: Int

    /// The number of logical lines in the buffer.
    public var lineCount: Int {
        storage.count - gapLength
    }

    /// Array-based access to lines (materializes the logical view).
    /// This property is provided for backward compatibility.
    public var lines: [String] {
        get {
            var result = [String]()
            result.reserveCapacity(lineCount)
            for i in 0..<gapStart {
                result.append(storage[i])
            }
            for i in (gapStart + gapLength)..<storage.count {
                result.append(storage[i])
            }
            return result
        }
        set {
            let vals = newValue.isEmpty ? [""] : newValue
            storage = ContiguousArray(vals)
            // Place gap at the end with no gap space
            gapStart = vals.count
            gapLength = 0
        }
    }

    public var isEmpty: Bool { lineCount == 1 && line(at: 0).isEmpty }

    public static func splitLines(from content: String) -> [String] {
        if content.isEmpty {
            return [""]
        }

        return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public init(_ content: String = "") {
        let split = Self.splitLines(from: content)
        storage = ContiguousArray(split)
        gapStart = split.count
        gapLength = 0
    }

    public init(lines: [String]) {
        let vals = lines.isEmpty ? [""] : lines
        storage = ContiguousArray(vals)
        gapStart = vals.count
        gapLength = 0
    }

    /// Returns the line at the given logical index, or an empty string if out of bounds.
    public func line(at index: Int) -> String {
        guard index >= 0 && index < lineCount else { return "" }
        return storage[physicalIndex(index)]
    }

    /// Sets the line at the given logical index.
    public mutating func setLine(at index: Int, to value: String) {
        guard index >= 0 && index < lineCount else { return }
        storage[physicalIndex(index)] = value
    }

    /// Inserts a line at the given logical index.
    public mutating func insertLine(_ line: String, at index: Int) {
        let count = lineCount
        guard index >= 0 && index <= count else { return }
        moveGap(to: index)
        if gapLength == 0 {
            growGap()
        }
        storage[gapStart] = line
        gapStart += 1
        gapLength -= 1
    }

    /// Removes the line at the given logical index.
    @discardableResult
    public mutating func removeLine(at index: Int) -> String {
        guard index >= 0 && index < lineCount else { return "" }
        moveGap(to: index)
        // The line to remove is now at storage[gapStart + gapLength] (right after gap)
        // Actually, after moveGap(to: index), the gap starts at index.
        // The element at logical index is now at storage[gapStart + gapLength]
        // Wait -- let me reconsider. When gap is at index, logical[index] maps to
        // storage[gapStart + gapLength].
        let phys = gapStart + gapLength
        let removed = storage[phys]
        storage[phys] = ""  // Clear reference
        gapLength += 1
        return removed
    }

    /// Reconstructs the full text by joining lines with newlines.
    public var text: String {
        var result = ""
        let count = lineCount
        for i in 0..<count {
            if i > 0 { result += "\n" }
            result += storage[physicalIndex(i)]
        }
        return result
    }

    // MARK: - Private

    /// Converts a logical line index to a physical storage index.
    @inline(__always)
    private func physicalIndex(_ logical: Int) -> Int {
        if logical < gapStart {
            return logical
        }
        return logical + gapLength
    }

    /// Moves the gap so it starts at the given logical index.
    private mutating func moveGap(to index: Int) {
        if index == gapStart { return }

        if gapLength == 0 {
            // No gap to move — just reposition the logical gap start.
            gapStart = index
            return
        }

        if index < gapStart {
            // Move elements from before gap to after gap
            let moveCount = gapStart - index
            let src = index
            let dst = index + gapLength
            // Move in reverse to avoid overwriting
            for i in stride(from: moveCount - 1, through: 0, by: -1) {
                storage[dst + i] = storage[src + i]
                storage[src + i] = ""
            }
        } else {
            // Move elements from after gap to before gap
            let moveCount = index - gapStart
            let src = gapStart + gapLength
            let dst = gapStart
            for i in 0..<moveCount {
                storage[dst + i] = storage[src + i]
                storage[src + i] = ""
            }
        }
        gapStart = index
    }

    /// Doubles the gap size when it's exhausted.
    private mutating func growGap() {
        let newGapSize = max(16, lineCount)
        // Insert newGapSize empty slots at gapStart + gapLength
        var newStorage = ContiguousArray<String>()
        newStorage.reserveCapacity(storage.count + newGapSize)

        // Copy before gap
        for i in 0..<gapStart {
            newStorage.append(storage[i])
        }
        // Add new gap
        for _ in 0..<(gapLength + newGapSize) {
            newStorage.append("")
        }
        // Copy after gap
        for i in (gapStart + gapLength)..<storage.count {
            newStorage.append(storage[i])
        }

        storage = newStorage
        gapLength += newGapSize
    }
}
