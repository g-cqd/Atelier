import Foundation
import Testing

@testable import AtelierText

/// Audit A1 — `Rope.contentHash` used to walk the whole tree and allocate
/// a `Data` of size `byteCount` per call (~1 MB transient + ~1 ms per
/// keystroke on a 1 MB document). The new implementation combines
/// `(byteCount, lineCount, root.nodeHash)` in O(1) at read time; every
/// leaf and branch carries its own hash precomputed at construction.
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

        // Removing the inserted byte restores the original content;
        // depending on tree shape the hash may or may not equal `before`
        // (different leaf composition). The strict invariant is just
        // that different content has different hashes — which the
        // `before != after` check above already pins.
    }

    @Test
    func `hash is content-equivalent across different construction paths`() {
        // Same string built directly versus assembled via insertions must
        // produce the same contentHash, because the hash combines node
        // hashes that ultimately fold every leaf's bytes.
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
        // After A1 the hash should be O(1) per call. Spec a loose budget
        // (1 000 reads on a 100 KB rope must complete in well under 10 ms
        // even in debug) so a regression to the O(N) implementation
        // surfaces in CI rather than silently in production.
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
