import Foundation
import Testing

@testable import KittyText

@Suite struct TextSelectionExtractionTests {
    @Test func `extractText single-line selection`() {
        let lines = ["hello world"]
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 6),
            head: TextPosition(row: 0, col: 11)
        )
        let result = selection.extractText(from: { lines[$0] }, lineCount: lines.count)
        #expect(result == "world")
    }

    @Test func `extractText multi-line selection`() {
        let lines = ["first", "middle", "last"]
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 2, col: 3)
        )
        let result = selection.extractText(from: { lines[$0] }, lineCount: lines.count)
        #expect(result == "rst\nmiddle\nlas")
    }

    @Test func `extractText reversed selection produces same result as forward`() {
        let lines = ["first", "middle", "last"]
        let forward = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 2, col: 3)
        )
        let reversed = TextSelection(
            anchor: TextPosition(row: 2, col: 3),
            head: TextPosition(row: 0, col: 2)
        )
        let forwardResult = forward.extractText(from: { lines[$0] }, lineCount: lines.count)
        let reversedResult = reversed.extractText(from: { lines[$0] }, lineCount: lines.count)
        #expect(forwardResult == reversedResult)
    }
}
