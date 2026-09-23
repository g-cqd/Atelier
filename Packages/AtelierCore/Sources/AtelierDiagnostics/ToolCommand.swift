public import Foundation

/// Builds the argv each diagnostic tool is launched with, what its exit codes mean, and how long it may run.
public enum ToolCommand {
    /// The arguments to analyze `files` under `root`. Tools with ``DiagnosticTool/AnalysisScope-swift.enum/corpus``
    /// scope analyze `root` as a whole and ignore `files`.
    ///
    /// swiftlint and Lockwood's swiftformat get no file arguments: given explicit paths they skip the project's own
    /// `included:`/`excluded:` lists and `--exclude` globs, so they run over the root the way the project runs them.
    /// arcleak also reads all of `root` and reports only on `files`, one `--only` each: its `mutual-strong-properties`
    /// rule needs every type in the module, and a run over the files alone would prune its shared facts cache to them.
    /// arcleak, dolly and deadwood write their SARIF paths relative to `root`, which `--relative-to` resolves the way
    /// they resolve the paths they report.
    public static func analyze(_ tool: DiagnosticTool, files: [String], root: URL) -> [String] {
        switch tool {
            case .swiftlint:
                ["lint", "--reporter", "sarif", "--quiet"]
            case .swiftFormat:
                ["lint", "--configuration", root.appending(path: ".swift-format").path] + files
            case .swiftformat:
                ["--lint", "."]
            case .arcleak:
                ["analyze", root.path] + files.flatMap { ["--only", $0] } + rootRelativeSARIF(root)
            case .dolly, .deadwood:
                ["analyze", root.path] + rootRelativeSARIF(root)
        }
    }

    /// SARIF output with every path relative to `root`.
    private static func rootRelativeSARIF(_ root: URL) -> [String] {
        ["--format", "sarif", "--relative-to", root.path]
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

    /// The exit codes that mean the run stopped short, which count as a completed run only when standard output still
    /// parses as the tool's report: 70 from arcleak, dolly and deadwood, whether every file was skipped or the run was
    /// cancelled, which prints nothing.
    public static func exitCodesAcceptedWithParsableOutput(_ tool: DiagnosticTool) -> Set<Int32> {
        switch tool {
            case .arcleak, .dolly, .deadwood: [70]
            case .swiftlint, .swiftFormat, .swiftformat: []
        }
    }

    /// How long one run may take before it is terminated: five minutes for a tool that reads all of the root, arcleak
    /// included, and one for swift-format, which reads only the files it is given.
    public static func timeout(_ tool: DiagnosticTool) -> Duration {
        switch tool {
            case .swiftFormat: .seconds(60)
            case .swiftlint, .swiftformat, .arcleak, .dolly, .deadwood: .seconds(300)
        }
    }
}
