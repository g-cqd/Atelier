import Foundation
import Testing

@testable import AtelierDiagnostics

/// SARIF 2.1.0 fragments decoded without a real tool run.
struct SARIFDecoderTests {
    private static let root = URL(filePath: "/repo")

    private static func sarif(runs: String) -> Data {
        Data(
            """
            {"version": "2.1.0", "runs": [\(runs)]}
            """
            .utf8
        )
    }

    @Test
    func `a swiftlint-shaped result with a file URI and a warning level decodes`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"ruleId": "line_length", "level": "warning",
                     "message": {"text": "Line too long"},
                     "locations": [{"physicalLocation": {
                         "artifactLocation": {"uri": "file:///repo/Sources/A.swift"},
                         "region": {"startLine": 10, "startColumn": 3}
                     }}]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .swiftlint, root: Self.root)
        #expect(
            findings == [
                Finding(
                    tool: .swiftlint, ruleID: "line_length", message: "Line too long", file: "Sources/A.swift",
                    line: 10,
                    column: 3, severity: .warning
                )
            ])
    }

    @Test
    func `an arcleak-shaped result with an error level and a full region decodes`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"ruleId": "retain-cycle", "level": "error",
                     "message": {"text": "Retain cycle"},
                     "locations": [{"physicalLocation": {
                         "artifactLocation": {"uri": "file:///repo/Sources/B.swift"},
                         "region": {"startLine": 5, "startColumn": 1, "endLine": 7, "endColumn": 2}
                     }}]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .arcleak, root: Self.root)
        #expect(
            findings == [
                Finding(
                    tool: .arcleak, ruleID: "retain-cycle", message: "Retain cycle", file: "Sources/B.swift", line: 5,
                    column: 1, endLine: 7, endColumn: 2, severity: .error
                )
            ])
    }

    @Test
    func `a dolly-shaped result carries related locations`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"ruleId": "duplicate", "level": "warning",
                     "message": {"text": "Duplicate block"},
                     "locations": [{"physicalLocation": {
                         "artifactLocation": {"uri": "file:///repo/Sources/C.swift"},
                         "region": {"startLine": 1}
                     }}],
                     "relatedLocations": [
                         {"physicalLocation": {"artifactLocation": {"uri": "file:///repo/Sources/D.swift"},
                             "region": {"startLine": 20}}, "message": {"text": "First copy"}},
                         {"physicalLocation": {"artifactLocation": {"uri": "file:///repo/Sources/E.swift"},
                             "region": {"startLine": 30}}, "message": {"text": "Second copy"}}
                     ]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .dolly, root: Self.root)
        #expect(findings.count == 1)
        #expect(
            findings[0].related == [
                RelatedLocation(file: "Sources/D.swift", line: 20, message: "First copy"),
                RelatedLocation(file: "Sources/E.swift", line: 30, message: "Second copy")
            ])
    }

    @Test
    func `a relative URI is used as-is with a leading dot-slash stripped`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"level": "note", "message": {"text": "Note"},
                     "locations": [{"physicalLocation": {
                         "artifactLocation": {"uri": "./Sources/F.swift"},
                         "region": {"startLine": 1}
                     }}]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .deadwood, root: Self.root)
        #expect(findings[0].file == "Sources/F.swift")
    }

    @Test
    func `an absolute URI outside the root is kept whole`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"level": "error", "message": {"text": "Outside"},
                     "locations": [{"physicalLocation": {
                         "artifactLocation": {"uri": "file:///elsewhere/G.swift"},
                         "region": {"startLine": 1}
                     }}]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .deadwood, root: Self.root)
        #expect(findings[0].file == "/elsewhere/G.swift")
    }

    @Test
    func `a missing region defaults to line one with nil columns`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"message": {"text": "No region"},
                     "locations": [{"physicalLocation": {"artifactLocation": {"uri": "H.swift"}}}]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .swiftlint, root: Self.root)
        #expect(findings[0].line == 1)
        #expect(findings[0].column == nil)
    }

    @Test(arguments: [
        (nil, Finding.Severity.warning), ("none", .note), ("note", .note), ("warning", .warning),
        ("error", .error), ("bogus", .warning)
    ])
    func `a missing or unknown level defaults to warning, others map directly`(
        level: String?, expected: Finding.Severity
    ) throws {
        let levelField = level.map { "\"level\": \"\($0)\", " } ?? ""
        let data = Self.sarif(
            runs: """
                {"results": [
                    {\(levelField)"message": {"text": "Msg"},
                     "locations": [{"physicalLocation": {"artifactLocation": {"uri": "I.swift"},
                         "region": {"startLine": 1}}}]}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .swiftlint, root: Self.root)
        #expect(findings[0].severity == expected)
    }

    @Test
    func `a result with no location is skipped`() throws {
        let data = Self.sarif(
            runs: """
                {"results": [
                    {"message": {"text": "No location"}, "locations": []}
                ]}
                """
        )
        let findings = try SARIFDecoder.findings(from: data, tool: .swiftlint, root: Self.root)
        #expect(findings.isEmpty)
    }

    @Test
    func `malformed JSON throws invalidJSON`() {
        #expect(throws: SARIFDecoder.DecodeError.self) {
            try SARIFDecoder.findings(from: Data("not json".utf8), tool: .swiftlint, root: Self.root)
        }
    }
}
