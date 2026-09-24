/// A parser state's LR(1) items, stored compactly: its LR(0) items, each with the terminals that may follow it as a
/// bit set over the grammar's lookahead terminals, one run of `wordCount` words per item.
///
/// One `LRItem` per item and lookahead, each holding its terminal's name, took most of the memory of compiling a large
/// grammar: Swift's states hold millions of such pairs.
struct LookaheadItemSet: Sendable {
    typealias CoreItem = CoreItemSetBuilder.CoreItem

    /// The items that have lookaheads, in a fixed order.
    let items: [CoreItem]
    let wordCount: Int
    /// `wordCount` words per item of ``items``, in order.
    private let words: [UInt64]

    /// The items of `items` whose run of `words` has a terminal set.
    init(items: [CoreItem], words: ArraySlice<UInt64>, wordCount: Int) {
        var keptItems: [CoreItem] = []
        var keptWords: [UInt64] = []
        keptItems.reserveCapacity(items.count)
        keptWords.reserveCapacity(words.count)
        for (index, item) in items.enumerated() {
            let run = words.dropFirst(index * wordCount).prefix(wordCount)
            guard run.contains(where: { $0 != 0 }) else { continue }
            keptItems.append(item)
            keptWords.append(contentsOf: run)
        }
        self.items = keptItems
        self.words = keptWords
        self.wordCount = wordCount
    }

    /// Calls `body` with the index of each terminal that may follow item `index`, in increasing order.
    func forEachLookahead(ofItemAt index: Int, _ body: (Int) -> Void) {
        for word in 0 ..< wordCount {
            var bits = words[index * wordCount + word]
            while bits != 0 {
                body(word << 6 | bits.trailingZeroBitCount)
                bits &= bits - 1
            }
        }
    }

    /// The lookaheads of item `index`, as their run of words.
    func lookaheadWords(ofItemAt index: Int) -> ArraySlice<UInt64> {
        words[index * wordCount ..< (index + 1) * wordCount]
    }
}

/// Bit set arithmetic over runs of words, the lookaheads of one item.
enum TerminalBits {
    /// The index of the word holding terminal `index`, and its bit.
    static func position(of index: Int) -> (word: Int, bit: UInt64) {
        (index >> 6, 1 << UInt64(index & 63))
    }
}
