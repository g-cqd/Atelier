import Foundation
import Testing

@testable import AtelierDiagnostics

/// The argv, standard input, exit-code and time-budget contracts ``ToolCommand`` builds for each tool.
struct ToolCommandTests {
    private static let root = URL(filePath: "/repo")

    @Test(arguments: [
        (DiagnosticTool.swiftlint, ["lint", "--reporter", "sarif", "--quiet"]),
        (.swiftFormat, ["lint", "--configuration", "/repo/.swift-format", "/repo/A.swift", "/repo/B.swift"]),
        (.swiftformat, ["--lint", "."]),
        (.arcleak, ["analyze", "/repo", "--only-from", "-", "--format", "sarif", "--relative-to", "/repo"]),
        (.dolly, ["analyze", "/repo", "--only-from", "-", "--format", "sarif", "--relative-to", "/repo"]),
        (.deadwood, ["analyze", "/repo", "--only-from", "-", "--format", "sarif", "--relative-to", "/repo"])
    ])
    func `analyze builds the expected argv for each tool`(tool: DiagnosticTool, expected: [String]) {
        #expect(ToolCommand.analyze(tool, files: ["/repo/A.swift", "/repo/B.swift"], root: Self.root) == expected)
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `an analyzer is given its files on standard input, one path per line`(tool: DiagnosticTool) {
        let files = ["/repo/A.swift", "/repo/Sub Dir/B.swift"]
        #expect(ToolCommand.standardInput(tool, files: files) == Data("/repo/A.swift\n/repo/Sub Dir/B.swift\n".utf8))
    }

    @Test(arguments: [DiagnosticTool.swiftlint, .swiftFormat, .swiftformat])
    func `a tool that is not an analyzer gets no standard input`(tool: DiagnosticTool) {
        #expect(ToolCommand.standardInput(tool, files: ["/repo/A.swift"]) == nil)
    }

    @Test(arguments: [
        "/repo/A\nB.swift", "/repo/A\rB.swift", "/repo/A\u{2028}B.swift", "/repo/A.swift ", " /repo/A.swift",
        "/repo/A.swift\t", "\"A.swift\""
    ])
    func `a path that standard input would alter is passed as --only, with no standard input`(path: String) {
        let files = ["/repo/B.swift", path]
        let expected = [
            "analyze", "/repo", "--only", "/repo/B.swift", "--only", path, "--format", "sarif", "--relative-to", "/repo"
        ]
        for tool in [DiagnosticTool.arcleak, .dolly, .deadwood] {
            #expect(ToolCommand.standardInput(tool, files: files) == nil)
            #expect(ToolCommand.analyze(tool, files: files, root: Self.root) == expected)
        }
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `a lone quote and a quote inside a path stay on standard input, since neither wraps the path`(
        tool: DiagnosticTool
    ) {
        let files = ["\"", "/repo/\"A.swift"]
        #expect(
            ToolCommand.analyze(tool, files: files, root: Self.root)
                == ["analyze", "/repo", "--only-from", "-", "--format", "sarif", "--relative-to", "/repo"])
        #expect(ToolCommand.standardInput(tool, files: files) == Data("\"\n/repo/\"A.swift\n".utf8))
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `each analyzer writes its SARIF paths relative to the root, spaces and all`(tool: DiagnosticTool) {
        let root = URL(filePath: "/Users/me/My Repo")
        let arguments = ToolCommand.analyze(tool, files: ["/Users/me/My Repo/A.swift"], root: root)

        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--relative-to" && $1 == "/Users/me/My Repo" })
    }

    @Test(arguments: DiagnosticTool.allCases)
    func `version is dash-dash-version for every tool`(tool: DiagnosticTool) {
        #expect(ToolCommand.version(tool) == ["--version"])
    }

    @Test(arguments: [
        (DiagnosticTool.swiftlint, Set<Int32>([0, 1, 2, 3])),
        (.swiftFormat, Set<Int32>([0, 1])),
        (.swiftformat, Set<Int32>([0, 1])),
        (.arcleak, Set<Int32>([0, 1])),
        (.dolly, Set<Int32>([0, 1])),
        (.deadwood, Set<Int32>([0, 1]))
    ])
    func `acceptable exit codes match each tool's meaning of nonzero`(tool: DiagnosticTool, expected: Set<Int32>) {
        #expect(ToolCommand.acceptableExitCodes(tool) == expected)
    }

    @Test(arguments: [
        (DiagnosticTool.arcleak, Set<Int32>([70])),
        (.dolly, Set<Int32>([70])),
        (.deadwood, Set<Int32>([70])),
        (.swiftlint, Set<Int32>()),
        (.swiftFormat, Set<Int32>()),
        (.swiftformat, Set<Int32>())
    ])
    func `only the analyzers' exit 70 counts, and only when their output parses`(
        tool: DiagnosticTool, expected: Set<Int32>
    ) {
        #expect(ToolCommand.exitCodesAcceptedWithParsableOutput(tool) == expected)
    }

    @Test(arguments: [
        (DiagnosticTool.swiftFormat, Duration.seconds(60)),
        (.swiftlint, .seconds(300)),
        (.swiftformat, .seconds(300)),
        (.arcleak, .seconds(300)),
        (.dolly, .seconds(300)),
        (.deadwood, .seconds(300))
    ])
    func `a tool that reads the whole root gets five minutes, and swift-format one`(
        tool: DiagnosticTool, expected: Duration
    ) {
        #expect(ToolCommand.timeout(tool) == expected)
    }
}
