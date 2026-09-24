import Foundation
import Testing

@testable import AtelierText

@Suite struct TextCoreWave3Tests {
    @Test func `rope stays balanced after one megabyte of appends and removals`() {
        var rope = Rope()
        for _ in 0 ..< 170_000 { rope.insert("abcde\n", atByteOffset: rope.byteCount) }
        func isBalanced(_ rope: Rope) -> Bool {
            let shape = rope._testTreeShape
            return shape.height <= Int(2 * log2(Double(shape.leafCount))) + 2
        }
        #expect(isBalanced(rope))
        var seed: UInt64 = 17
        for _ in 0 ..< 1_000 {
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let start = Int(seed % UInt64(rope.byteCount))
            rope.remove(start ..< min(rope.byteCount, start + 90))
        }
        #expect(isBalanced(rope))
    }

    @Test(arguments: [UInt64(0xC0FFEE), 17, 0xBAD5EED])
    func `large random edits preserve lines offsets bytes and AVL balance`(initialSeed: UInt64) {
        let initial = Array(String(repeating: "line\r\n界🙂\rlone\n", count: 4_096).utf8.prefix(65_536))
        var rope = Rope(bytes: Data(initial))
        var reference = initial
        var seed = initialSeed
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed % UInt64(bound))
        }
        let fragments = ["a", "\n", "\r", "\r\n", "界", "🙂", "xy\t"]
        for _ in 0 ..< 300 {
            var starts = [0]
            for (index, byte) in reference.enumerated() where byte == 0x0A { starts.append(index + 1) }
            let lineIndex = next(starts.count + 1)
            let value = String(repeating: fragments[next(fragments.count)], count: next(1_000) + 1)
            let offset = next(reference.count + 1)
            let upper = min(reference.count, offset + next(8_192) + 1)
            switch next(5) {
                case 0:
                    rope.insert(value, atByteOffset: offset)
                    reference.insert(contentsOf: value.utf8, at: offset)
                case 1:
                    rope.remove(offset ..< upper)
                    reference.removeSubrange(offset ..< upper)
                case 2:
                    rope.replace(offset ..< upper, with: value)
                    reference.replaceSubrange(offset ..< upper, with: value.utf8)
                case 3:
                    rope.insertLine(value, at: lineIndex)
                    if lineIndex == starts.count {
                        reference.append(contentsOf: ("\n" + value).utf8)
                    } else {
                        reference.insert(contentsOf: (value + "\n").utf8, at: starts[lineIndex])
                    }
                default:
                    let lineIndex = min(lineIndex, starts.count - 1)
                    let end = lineIndex + 1 < starts.count ? starts[lineIndex + 1] : reference.count
                    let lineEnd = lineIndex + 1 < starts.count ? end - 1 : end
                    let expected = String(decoding: reference[starts[lineIndex] ..< lineEnd], as: UTF8.self)
                    #expect(rope.removeLine(at: lineIndex) == expected)
                    if starts.count == 1 {
                        reference.removeAll()
                    } else if lineIndex == starts.count - 1 {
                        reference.removeSubrange((starts[lineIndex] - 1) ..< reference.count)
                    } else {
                        reference.removeSubrange(starts[lineIndex] ..< end)
                    }
            }
            let lines = reference.split(separator: 0x0A, omittingEmptySubsequences: false)
                .map { String(decoding: $0, as: UTF8.self) }
            #expect(rope._testAllNodesBalanced)
            #expect(rope.bytes(in: 0 ..< rope.byteCount) == Data(reference))
            #expect(rope.text == String(decoding: reference, as: UTF8.self))
            #expect(rope.allLines == lines)
            #expect(rope.lineCount == lines.count)
            rope.invalidateSnapshotCaches()
            var nextStarts = [0]
            for (index, byte) in reference.enumerated() where byte == 0x0A { nextStarts.append(index + 1) }
            for index in [0, next(lines.count), lines.count - 1] {
                #expect(rope.line(at: index) == lines[index])
                #expect(rope.byteOffset(forLine: index) == nextStarts[index])
            }
            let lowerLine = next(lines.count)
            let upperLine = min(lines.count, lowerLine + next(32) + 1)
            #expect(rope.lines(in: lowerLine ..< upperLine) == Array(lines[lowerLine ..< upperLine]))
            let lowerByte = next(reference.count + 1)
            let upperByte = min(reference.count, lowerByte + next(8_192))
            #expect(rope.bytes(in: lowerByte ..< upperByte) == Data(reference[lowerByte ..< upperByte]))
        }
    }

    @Test func `mutating a document buffer invalidates derived snapshots`() {
        let document = TextDocument(filePath: "/tmp/example", fileName: "example", content: "old\ntext", language: nil)
        _ = document.fileContent
        _ = document.documentText
        _ = document.serializedByteCount
        document.cachedMaxLineWidth = 99
        document.textBuffer.setLine(at: 0, to: "new")
        #expect(document.documentText == "new\ntext")
        #expect(document.fileContent == ["new", "text"])
        #expect(document.serializedByteCount == "new\ntext".utf8.count)
        #expect(document.cachedMaxLineWidth == nil)
    }

    @Test func `data slices keep their own byte indices when building a rope`() {
        let data = Data(repeating: UInt8(ascii: "x"), count: 900) + Data("before\ninside\nafter".utf8)
        let slice = data[900 ..< data.endIndex]
        let rope = Rope(bytes: slice)
        #expect(rope.text == "before\ninside\nafter")
        #expect(rope.allLines == ["before", "inside", "after"])
    }

    @Test func `whole document deletion and replacement leave a balanced rope`() {
        let content = String(repeating: "wide line\n", count: 100_000)
        var rope = Rope(content)
        rope.remove(0 ..< rope.byteCount)
        #expect(rope.text.isEmpty)
        #expect(rope._testAllNodesBalanced)
        rope = Rope(content)
        rope.replace(0 ..< rope.byteCount, with: "replacement")
        #expect(rope.text == "replacement")
        #expect(rope._testAllNodesBalanced)
    }

    @Test func `batched maximum width agrees with individual line reads`() {
        let buffer = TextBuffer(String(repeating: "abc\t界\n", count: 9_001))
        let range = 3_999 ..< 8_201
        let expected = range.reduce(0) {
            max($0, TextDisplayMetrics.displayWidth(of: buffer.line(at: $1), tabSize: 4))
        }
        #expect(buffer.maxLineWidth(in: range, tabSize: 4) == expected)
    }

    @Test func `ASCII width fast path agrees with character measurement`() {
        var seed: UInt64 = 91
        let symbols = Array("abcXYZ0123456789 \t\r\n")
        for _ in 0 ..< 500 {
            var line = ""
            for _ in 0 ..< 80 {
                seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                line.append(symbols[Int(seed % UInt64(symbols.count))])
            }
            for tabSize in [1, 4, 8] {
                var expected = 0
                for character in line {
                    expected +=
                        character == "\t" ? tabSize - expected % tabSize : UnicodeWidth.displayWidth(of: character)
                }
                #expect(TextDisplayMetrics.displayWidth(of: line, tabSize: tabSize) == expected)
            }
        }
    }

    @Test func `display widths agree with character measurement for mixed text`() {
        var seed: UInt64 = 37
        let parts = ["a", "\t", "\n", "界", "🙂", "\0", "e\u{301}", "🇫🇷"]
        for _ in 0 ..< 500 {
            var line = ""
            for _ in 0 ..< 40 {
                seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                line += parts[Int(seed % UInt64(parts.count))]
            }
            for tabSize in [1, 4, 8] {
                var expected = 0
                for character in line {
                    expected +=
                        character == "\t" ? tabSize - expected % tabSize : UnicodeWidth.displayWidth(of: character)
                }
                #expect(TextDisplayMetrics.displayWidth(of: line, tabSize: tabSize) == expected)
            }
            let newlineCount = line.filter { $0 == "\n" }.count
            #expect(Rope.countNewlines(in: Data(line.utf8)) == newlineCount)
            #expect(Rope(line).lineCount == newlineCount + 1)
        }
        #expect(TextDisplayMetrics.displayWidth(of: "a\r\nb") == 3)
    }
}
