import AtelierDiff
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering

/// A CRLF file's lines lose their `\r` when the diff cuts them, but its colours land on the same columns as the same
/// file with LF endings: no drift from one line to the next, and nothing coloured past a line's last character.
struct CRLFTokenTests {
    private static let lf = """
        let a = 1 // one
        let name = "é" // accented
        /* block */ var b = 2
        let unterminated = "open
        let last = 3 // no newline at the end
        """

    private static func tokens(_ text: String) -> LineTokens {
        DiffRenderer.tokensByLine(text: text, lines: DiffModel.lines(of: text), language: .swift)
    }

    @Test
    func `a CRLF file colours the same columns as its LF twin`() {
        let crlf = Self.lf.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(Self.tokens(crlf) == Self.tokens(Self.lf))
    }

    @Test
    func `a CRLF file that ends with a newline colours like its LF twin`() {
        let lf = Self.lf + "\n"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(Self.tokens(crlf) == Self.tokens(lf))
    }
}
