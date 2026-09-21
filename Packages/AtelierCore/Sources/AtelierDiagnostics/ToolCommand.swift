public import Foundation

/// Builds the argv each diagnostic tool is launched with, and what its exit codes mean.
public enum ToolCommand {
    /// The arguments to analyze `files` under `root`. Tools with ``DiagnosticTool/AnalysisScope-swift.enum/corpus``
    /// scope analyze `root` as a whole and ignore `files`.
    ///
    /// swiftlint takes no file or path arguments at all: given explicit paths, SwiftLint analyzes exactly those
    /// paths and never consults its own `included:`/`excluded:` lists, so a project's `.swiftlint.yml` is silently
    /// bypassed. Run with no arguments and the analysis root as its current directory, SwiftLint discovers
    /// `.swiftlint.yml` there itself and honors those lists exactly as the project's own `swiftlint` runs do; the
    /// engine narrows the resulting findings back down to the changed files afterward.
    ///
    /// Lockwood's swiftformat is given the same treatment and for the same reason: pointed at explicit files it
    /// still discovers a nearby `.swiftformat`, but per-directory `--exclude` globs only apply while it is
    /// traversing on its own, so it is run as `swiftformat --lint .` over the analysis root and its findings are
    /// narrowed back down afterward, exactly like swiftlint's.
    public static func analyze(_ tool: DiagnosticTool, files: [String], root: URL) -> [String] {
        switch tool {
            case .swiftlint:
                ["lint", "--reporter", "sarif", "--quiet"]
            case .swiftFormat:
                ["lint", "--configuration", root.appending(path: ".swift-format").path] + files
            case .swiftformat:
                ["--lint", "."]
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
            case .swiftFormat, .swiftformat: [0, 1]
            case .arcleak, .dolly, .deadwood: [0, 1]
        }
    }
}
