import Foundation
import Testing

@testable import AtelierText

/// ``Rope/contentHash``: stable across reads and copies, changed by an edit, and O(1) per read.
@Suite
struct RopeContentHashTests {
    @Test
    func `hash is stable across repeated reads without mutation`() {
        let rope = Rope("the quick brown fox jumps over the lazy dog")
        let first = rope.contentHash
        for _ in 0 ..< 10 {
            #expect(rope.contentHash == first)
        }
    }

    @Test
    func `hash differs after any single-byte change`() {
        let rope = Rope("alpha beta gamma")
        let before = rope.contentHash

        var mutated = rope
        mutated.insert("X", atByteOffset: 5)
        let after = mutated.contentHash
        #expect(before != after, "single-byte insertion must change the hash")

        // Removing the byte again restores the bytes but not necessarily the leaves, so the hash need not return to
        // `before`.
    }

    @Test
    func `hash is content-equivalent across different construction paths`() {
        // Short enough to stay one leaf either way, so both ropes hold the same leaves.
        let direct = Rope("hello world")

        var assembled = Rope("hello")
        assembled.insert(" world", atByteOffset: 5)

        #expect(direct.contentHash == assembled.contentHash)
    }

    @Test
    func `cloned storage produces the same hash`() {
        // A `Rope` value is shared via CoW until a mutation occurs. Any
        // copy must hash identically.
        let original = Rope("identity check")
        let copy = original
        #expect(original.contentHash == copy.contentHash)
    }

    @Test
    func `hash respects byteCount and lineCount`() {
        // Two ropes with the same bytes but different line structure
        // can't exist (lineCount derives from \n count), but we still
        // want to confirm the hash inputs are stable.
        let r1 = Rope("line1\nline2")
        let r2 = Rope("line1\nline2")
        #expect(r1.contentHash == r2.contentHash)
        #expect(r1.byteCount == r2.byteCount)
        #expect(r1.lineCount == r2.lineCount)
    }

    @Test
    func `read-only hash does not allocate per call (microbenchmark sanity)`() {
        // O(1) per read: a loose budget, 1,000 reads of a 100 KB rope in under 10 ms even in debug, catches an O(n)
        // regression.
        var content = ""
        content.reserveCapacity(100_000)
        for _ in 0 ..< 2_000 { content += "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        let rope = Rope(content)

        let start = ContinuousClock.now
        var checksum = 0
        for _ in 0 ..< 1_000 {
            checksum &+= rope.contentHash
        }
        let elapsed = start.duration(to: .now)
        let elapsedMs =
            Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        #expect(
            elapsedMs < 10.0,
            "1 000 contentHash reads on a 100 KB rope took \(elapsedMs) ms — suspected O(N) regression"
        )
        // Touch the checksum so the compiler can't elide the loop.
        _ = checksum
    }
}
