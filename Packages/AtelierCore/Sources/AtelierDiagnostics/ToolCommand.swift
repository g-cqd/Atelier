public import Foundation

/// Builds the argv each diagnostic tool is launched with, and what its exit codes mean.
public enum ToolCommand {
    /// The arguments to analyze `files` under `root`. Tools with ``DiagnosticTool/AnalysisScope-swift.enum/corpus``
    /// scope analyze `root` as a whole and ignore `files`.
    public static func analyze(_ tool: DiagnosticTool, files: [String], root: URL) -> [String] {
        switch tool {
            case .swiftlint:
                ["lint", "--reporter", "sarif", "--quiet"] + files
            case .swiftFormat:
                ["lint"] + files
            case .arcleak:
                ["analyze"] + files + ["--format", "sarif"]
            case .dolly, .deadwood:
                ["analyze", root.path, "--format", "sarif"]
        }
    }

    /// The arguments that print the tool's version.
    public static func version(_ tool: DiagnosticTool) -> [String] {
        ["--version"]
    }

    /// The exit codes that mean the tool ran to completion, whether or not it found anything to report.
    public static func acceptableExitCodes(_ tool: DiagnosticTool) -> Set<Int32> {
        switch tool {
            case .swiftlint: [0, 1, 2, 3]
            case .swiftFormat: [0, 1]
            case .arcleak, .dolly, .deadwood: [0, 1]
        }
    }
}
