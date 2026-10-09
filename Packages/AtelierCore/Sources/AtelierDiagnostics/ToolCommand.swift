public import Foundation

/// Builds the argv each diagnostic tool is launched with, what its exit codes mean, and how long it may run.
public enum ToolCommand {
    /// The arguments to analyze `files` under `root`. Tools with ``DiagnosticTool/AnalysisScope-swift.enum/corpus``
    /// scope analyze `root` as a whole and ignore `files`, unless they ``DiagnosticTool/scopesItsOwnReport``.
    ///
    /// swiftlint and Lockwood's swiftformat get no file arguments: given explicit paths they skip the project's own
    /// `included:`/`excluded:` lists and `--exclude` globs, so they run over the root the way the project runs them.
    /// arcleak, dolly and deadwood all read all of `root` and scope their report to `files`, because their rules are
    /// cross-file: arcleak's `mutual-strong-properties` needs every type in the module, and dolly reports a clone group
    /// when any of its members is in scope. A run over the files alone would prune arcleak's shared facts cache to them
    /// and miss the members outside them. They take the files as `--only-from -`, one path per line on standard input
    /// (see ``standardInput(_:files:)``), so a long change set does not become a long argument list. All three write
    /// their SARIF paths relative to `root`, which `--relative-to` resolves the way they resolve the paths they report.
    public static func analyze(_ tool: DiagnosticTool, files: [String], root: URL) -> [String] {
        switch tool {
            case .swiftlint:
                ["lint", "--reporter", "sarif", "--quiet"]
            case .swiftFormat:
                ["lint", "--configuration", root.appending(path: ".swift-format").path] + files
            case .swiftformat:
                ["--lint", "."]
            case .arcleak, .dolly, .deadwood:
                ["analyze", root.path] + scopeArguments(files) + rootRelativeSARIF(root)
        }
    }

    /// The standard input that gives an analyzer `files`: each path on its own line, UTF-8, which `--only-from -`
    /// reads. Nil for a tool that is not given its files this way, and for a set that standard input cannot carry one
    /// path per line; ``analyze(_:files:root:)`` then passes those files as `--only` arguments instead.
    public static func standardInput(_ tool: DiagnosticTool, files: [String]) -> Data? {
        switch tool {
            case .arcleak, .dolly, .deadwood:
                canBeListedOnePerLine(files) ? Data(files.map { "\($0)\n" }.joined().utf8) : nil
            case .swiftlint, .swiftFormat, .swiftformat:
                nil
        }
    }

    /// The arguments that scope an analyzer's report to `files`: one `--only-from -`, or one `--only` per file when
    /// standard input cannot carry them.
    private static func scopeArguments(_ files: [String]) -> [String] {
        canBeListedOnePerLine(files) ? ["--only-from", "-"] : files.flatMap { ["--only", $0] }
    }

    /// Whether `--only-from` reads every path back as it was given. That reader splits on line breaks, drops empty
    /// lines, trims the spaces and tabs at each line's ends, and unquotes a path a pair of double quotes wraps. A path
    /// that any of those would alter falls back to `--only`, which takes its value verbatim.
    private static func canBeListedOnePerLine(_ files: [String]) -> Bool {
        files.allSatisfy { path in
            guard let first = path.first, let last = path.last else { return false }
            let isTrimmed: (Character) -> Bool = { $0 == " " || $0 == "\t" }
            let isQuoted = path.count >= 2 && first == "\"" && last == "\""
            return !path.contains(where: \.isNewline) && !isTrimmed(first) && !isTrimmed(last) && !isQuoted
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
