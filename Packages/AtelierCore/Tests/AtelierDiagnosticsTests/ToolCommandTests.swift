import Foundation
import Testing

@testable import AtelierDiagnostics

/// The argv, exit-code and time-budget contracts ``ToolCommand`` builds for each tool.
struct ToolCommandTests {
    private static let root = URL(filePath: "/repo")

    @Test(arguments: [
        (DiagnosticTool.swiftlint, ["lint", "--reporter", "sarif", "--quiet"]),
        (.swiftFormat, ["lint", "--configuration", "/repo/.swift-format", "/repo/A.swift", "/repo/B.swift"]),
        (.swiftformat, ["--lint", "."]),
        (
            .arcleak,
            [
                "analyze", "/repo", "--only", "/repo/A.swift", "--only", "/repo/B.swift", "--format", "sarif",
                "--relative-to", "/repo"
            ]
        ),
        (.dolly, ["analyze", "/repo", "--format", "sarif", "--relative-to", "/repo"]),
        (.deadwood, ["analyze", "/repo", "--format", "sarif", "--relative-to", "/repo"])
    ])
    func `analyze builds the expected argv for each tool`(tool: DiagnosticTool, expected: [String]) {
        #expect(ToolCommand.analyze(tool, files: ["/repo/A.swift", "/repo/B.swift"], root: Self.root) == expected)
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
