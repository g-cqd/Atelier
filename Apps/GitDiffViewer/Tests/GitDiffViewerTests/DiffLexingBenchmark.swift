import AppKit
import DiffCore
import Foundation
import Testing

@testable import DiffRendering

/// Opt-in timing of the lexical tier over one pair of 50,000-line Swift sides, in a release build: the lexing a
/// file's preparation runs (`tokensByLine` on both sides), the same for a plain-text file, and the render that
/// places the tokens (both split sides, every row). The scan alone is timed through the engine's two entry points,
/// the UTF-16 one the renderer called until the lexer moved to UTF-8, and the UTF-8 one it calls since.
///
/// A second test times the re-renders of a prepared pair that the window runs without lexing again: a layout toggle
/// (the inline pane, then both split sides, every row) and a gap drag (the split sides of a changes-only layout, once
/// per step as one gap opens).
///
/// `GDV_BENCH=1 swift test -c release --filter DiffLexingBenchmark`. `GDV_BENCH_OLD` and `GDV_BENCH_NEW` name the
/// two sides' files; without them a generated pair stands in. The checksum covers every coloured run of both
/// rendered sides, so two builds that print the same checksum place the same colours on the same UTF-16 ranges.
struct DiffLexingBenchmark {
    private static let iterations = 13
    private static let warmUps = 2

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `lexes and places the tokens of a fifty thousand line pair`() throws {
        let (old, new) = try Self.pair()
        let prepared = PreparedDiff(
            FileDiffInput(title: "pair.swift", oldText: old, newText: new, language: .swift), granularity: .word)
        let options = DiffRenderer.Options(granularity: .word, sides: [.old, .new])
        let oldLines = prepared.model.oldLines
        let newLines = prepared.model.newLines
        let engine = LexicalHighlightEngine()
        let oldBytes = Array(old.utf8)
        let newBytes = Array(new.utf8)
        var samples: [String: [Double]] = [:]
        var tokenCount = 0
        var checksum: UInt64 = 0
        for iteration in 0 ..< Self.iterations {
            // Each result is released before the next timed call, so no call pays for freeing another's.
            var lexed: [LineTokens] = []
            let lexing = Self.milliseconds {
                lexed.append(DiffRenderer.tokensByLine(text: old, lines: oldLines, language: .swift))
                lexed.append(DiffRenderer.tokensByLine(text: new, lines: newLines, language: .swift))
            }
            var scanned: [[HighlightToken]] = []
            let utf16Scan = Self.milliseconds {
                scanned.append(engine.highlight(utf16: Array(old.utf16), language: .swift))
                scanned.append(engine.highlight(utf16: Array(new.utf16), language: .swift))
            }
            let utf16Counts = scanned.map(\.count)
            scanned = []
            let utf8Scan = Self.milliseconds {
                scanned.append(engine.highlight(utf8: oldBytes, language: .swift))
                scanned.append(engine.highlight(utf8: newBytes, language: .swift))
            }
            let utf8Counts = scanned.map(\.count)
            #expect(utf8Counts == utf16Counts)
            var skipped: [LineTokens] = []
            let plain = Self.milliseconds {
                skipped.append(DiffRenderer.tokensByLine(text: old, lines: oldLines, language: .plain))
                skipped.append(DiffRenderer.tokensByLine(text: new, lines: newLines, language: .plain))
            }
            var rendered: RenderedDiff?
            let placement = Self.milliseconds {
                rendered = DiffRenderer.render(
                    prepared: [prepared], options: options, layout: .full, withHeaders: false)
            }
            let oldSide = try #require(rendered?.old)
            let newSide = try #require(rendered?.new)
            #expect(skipped.map(\.count) == [oldLines.count, newLines.count])
            #expect(skipped.joined().joined().isEmpty)
            if iteration == 0 {
                tokenCount = lexed.joined().map(\.count).reduce(0, +)
                checksum = Self.checksum(of: [oldSide.attributed, newSide.attributed])
            }
            guard iteration >= Self.warmUps else { continue }
            samples["lexing", default: []].append(lexing)
            samples["scan-utf16", default: []].append(utf16Scan)
            samples["scan-utf8", default: []].append(utf8Scan)
            samples["plain", default: []].append(plain)
            samples["placement", default: []].append(placement)
        }
        print(
            "BENCH gdv-pair old-lines \(oldLines.count) new-lines \(newLines.count) "
                + "bytes \(old.utf8.count + new.utf8.count) tokens \(tokenCount) checksum \(checksum)")
        for name in ["lexing", "scan-utf16", "scan-utf8", "plain", "placement"] {
            let sorted = samples[name, default: []].sorted()
            let rounded = sorted.map { ($0 * 1_000).rounded() / 1_000 }
            print("BENCH gdv-pair \(name) median \(sorted[sorted.count / 2]) ms samples \(rounded)")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `re-renders a prepared fifty thousand line pair as a layout toggle and a gap drag do`() throws {
        // One rewritten line in 97 leaves hunks of seven rows around gaps of ninety, so a drag has a gap to open.
        let (old, new) = try Self.pair(rewritingOneLineIn: 97)
        let prepared = PreparedDiff(
            FileDiffInput(title: "pair.swift", oldText: old, newText: new, language: .swift), granularity: .word)
        let inline = DiffRenderer.Options(granularity: .word, sides: [.unified])
        let split = DiffRenderer.Options(granularity: .word, sides: [.old, .new])
        let dragged = GapKey(fileIndex: 0, gapIndex: prepared.model.unifiedChangeStarts.count / 2)
        let steps = (0 ... Self.dragSteps).map { GapExpansion(below: $0 * 90 / Self.dragSteps) }
        var samples: [String: [Double]] = [:]
        var checksum: UInt64 = 0
        var dragRows = 0
        for iteration in 0 ..< Self.iterations {
            var toggled: [RenderedDiff] = []
            let toggle = Self.milliseconds {
                for options in [inline, split] {
                    toggled.append(
                        DiffRenderer.render(prepared: [prepared], options: options, layout: .full, withHeaders: false))
                }
            }
            var drag: [RenderedDiff] = []
            let dragging = Self.milliseconds {
                for expansion in steps {
                    drag.append(
                        DiffRenderer.render(
                            prepared: [prepared], options: split,
                            layout: .changes(context: 3, expansions: [dragged: expansion]), withHeaders: false))
                }
            }
            if iteration == 0 {
                let texts =
                    toggled.flatMap { [$0.unified, $0.old, $0.new].compactMap { $0?.attributed } }
                    + drag.flatMap { [$0.old, $0.new].compactMap { $0?.attributed } }
                try #require(texts.count == 3 + 2 * steps.count)
                checksum = Self.checksum(of: texts)
                dragRows = drag.map { $0.new?.rows.count ?? 0 }.reduce(0, +)
            }
            guard iteration >= Self.warmUps else { continue }
            samples["toggle", default: []].append(toggle)
            samples["gap-drag", default: []].append(dragging)
        }
        print(
            "BENCH gdv-rerender unified-rows \(prepared.model.unifiedRows.count) drag-steps \(steps.count) "
                + "drag-rows \(dragRows) checksum \(checksum)")
        for name in ["toggle", "gap-drag"] {
            let sorted = samples[name, default: []].sorted()
            let rounded = sorted.map { ($0 * 1_000).rounded() / 1_000 }
            print("BENCH gdv-rerender \(name) median \(sorted[sorted.count / 2]) ms samples \(rounded)")
        }
    }

    /// The renders one gap drag runs, one per step of the gap opening.
    private static let dragSteps = 12

    /// The two sides from `GDV_BENCH_OLD` and `GDV_BENCH_NEW`, or 50,000 generated lines whose new side rewrites one
    /// line in `stride`, every seventh by default.
    private static func pair(rewritingOneLineIn stride: Int = 7) throws -> (old: String, new: String) {
        let environment = ProcessInfo.processInfo.environment
        if let oldPath = environment["GDV_BENCH_OLD"], let newPath = environment["GDV_BENCH_NEW"] {
            let old = try Data(contentsOf: URL(fileURLWithPath: oldPath))
            let new = try Data(contentsOf: URL(fileURLWithPath: newPath))
            return (String(decoding: old, as: UTF8.self), String(decoding: new, as: UTF8.self))
        }
        let templates = [
            "/// Returns the value at `index`, or nil past the end — see ``Store``.",
            "@MainActor final class Store#: ObservableObject {",
            "    private var values: [String: Int] = [\"key#\": #, \"clé\": 0x1F]",
            "    let label = \"Item \\(#) ✓\" // the label shown in the list",
            "    func value(at index: Int) async throws -> Int? { guard index < # else { return nil }",
            "        /* a block /* nested */ comment */ return values[\"key\\(index)\"] ?? 1.5e3",
            "    }",
            "}"
        ]
        var old = ""
        var new = ""
        for index in 0 ..< 50_000 {
            let line = templates[index % templates.count].replacingOccurrences(of: "#", with: String(index))
            old += line + "\n"
            new += (index % stride == 3 ? line.replacingOccurrences(of: "value", with: "result") : line) + "\n"
        }
        return (old, new)
    }

    /// FNV-1a over each foreground colour run of `texts`: its UTF-16 range and the first role drawn in its colour.
    private static func checksum(of texts: [NSAttributedString]) -> UInt64 {
        let palette = DiffPalette.system
        let colors = HighlightRole.allCases.map { ($0, palette.color(for: $0)) }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for text in texts {
            let whole = NSRange(location: 0, length: text.length)
            text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
                let color = value as? NSColor
                let role = colors.first { $0.1 == color }.map { UInt64($0.0.rawValue) } ?? UInt64.max
                for field in [UInt64(range.location), UInt64(range.length), role] {
                    hash = (hash ^ field) &* 1_099_511_628_211
                }
            }
        }
        return hash
    }

    private static func milliseconds(_ body: () -> Void) -> Double {
        let elapsed = ContinuousClock().measure(body)
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
}
