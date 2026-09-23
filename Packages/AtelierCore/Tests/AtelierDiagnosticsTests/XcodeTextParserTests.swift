import Foundation
import Testing

@testable import AtelierDiagnostics

/// Xcode-format diagnostic lines, as swift-format lint emits them on stderr.
struct XcodeTextParserTests {
    private static let root = URL(filePath: "/repo")

    @Test
    func `each field of a well-formed line is extracted`() {
        let text = "/repo/Sources/A.swift:12:5: warning: [NoLeadingUnderscore] avoid leading underscores"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(
            findings == [
                Finding(
                    tool: .swiftFormat, ruleID: "NoLeadingUnderscore", message: "avoid leading underscores",
                    file: "Sources/A.swift", line: 12, column: 5, severity: .warning
                )
            ])
    }

    @Test
    func `noise lines that do not match the format are ignored`() {
        let text = """
            Linting 3 files
            /repo/Sources/A.swift:1:1: error: [Bad] broken
            done.
            """
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(findings.count == 1)
        #expect(findings[0].line == 1)
        #expect(findings[0].severity == .error)
    }

    @Test
    func `a message with no rule prefix keeps the tool as the rule id`() {
        let text = "/repo/B.swift:3:1: note: plain message"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(findings[0].ruleID == "swift-format")
        #expect(findings[0].message == "plain message")
    }

    @Test
    func `a parenthesized rule prefix, as swiftformat emits, is extracted the same way as a bracketed one`() {
        let text = "/repo/Sources/A.swift:12:5: warning: (trailingCommas) remove trailing comma"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftformat, root: Self.root)
        #expect(
            findings == [
                Finding(
                    tool: .swiftformat, ruleID: "trailingCommas", message: "remove trailing comma",
                    file: "Sources/A.swift", line: 12, column: 5, severity: .warning
                )
            ])
    }

    @Test
    func `a swiftformat message with no rule prefix keeps swiftformat as the rule id`() {
        let text = "/repo/B.swift:3:1: note: plain message"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftformat, root: Self.root)
        #expect(findings[0].ruleID == "swiftformat")
        #expect(findings[0].message == "plain message")
    }

    @Test
    func `an absolute path under the root becomes relative`() {
        let text = "/repo/Nested/C.swift:1:1: warning: [X] msg"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(findings[0].file == "Nested/C.swift")
    }

    @Test
    func `an absolute path outside the root is kept whole`() {
        let text = "/elsewhere/D.swift:1:1: warning: [X] msg"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(findings[0].file == "/elsewhere/D.swift")
    }

    @Test
    func `a path under a sibling whose name extends the root is kept whole`() {
        let text = "/repo-other/D.swift:1:1: warning: [X] msg"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(findings.map(\.file) == ["/repo-other/D.swift"])
    }

    @Test(arguments: ["error", "warning", "note"])
    func `each severity token maps to its Finding severity`(token: String) {
        let text = "/repo/E.swift:1:1: \(token): msg"
        let findings = XcodeTextParser.findings(from: text, tool: .swiftFormat, root: Self.root)
        #expect(findings.count == 1)
    }
}
