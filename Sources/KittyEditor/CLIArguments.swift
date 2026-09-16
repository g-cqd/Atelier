import ArgumentParser
import Foundation
import KittyTerminal
import System

/// Parses `CommandLine.arguments` into a structured launch action.
///
/// Internally backed by `apple/swift-argument-parser`. The wrapper keeps the
/// `parse([String]) -> Action` surface stable so existing tests and call
/// sites in `AppMain` don't need to change.
public struct CLIArguments: Sendable {
    public enum Action: Sendable {
        case run(LaunchConfig)
        case printVersion
        case printHelp
    }

    public struct LaunchConfig: Sendable {
        public var rootPath: String
        public var initialFile: String?
        public var initialLine: Int?
        public var initialColumn: Int?
        public var configPath: String?
        public var readOnly: Bool
        public var gitEnabled: Bool?
        public var syntaxEnabled: Bool?
        public var fileWatcherEnabled: Bool?
        public var symbolsEnabled: Bool?
        public var keybindingMode: String?
        public var tabSize: Int?
        public var wrapLines: Bool?
        public var themeForeground: String?
    }

    public static func parse(_ args: [String] = CommandLine.arguments) -> Action {
        // Drop argv[0]; the rest is what ArgumentParser sees.
        let arguments = Array(args.dropFirst())

        // `--help`/`-h` and `--version`/`-v` are intercepted so the caller can
        // print the message themselves (existing tests assert the enum case).
        if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) {
            return .printHelp
        }
        if arguments.contains(where: { $0 == "--version" || $0 == "-v" }) {
            return .printVersion
        }

        do {
            let parsed = try KittyCodeCommand.parse(arguments)
            return .run(parsed.toLaunchConfig())
        } catch {
            // ArgumentParser surfaces ValidationError / UnknownArgument /
            // MissingArgument as `error`. Render the canonical message,
            // route through KittyLogger.stderr, then exit with the same code
            // the old hand-rolled parser used.
            let message = KittyCodeCommand.message(for: error)
            KittyLogger.stderr(message)
            exit(1)
        }
    }

    // MARK: - Help / version text

    /// Composed at compile time from `BuildVersion.release` (see
    /// `Sources/KittyCode/Version.swift`). The release workflow
    /// (`.github/workflows/release.yml`) overwrites that file before
    /// `swift build -c release`, so tagged releases report their
    /// semantic version while local builds report `0.0.0-dev`. Audit D9.
    public static let versionString = "KittyCode \(BuildVersion.release)"

    /// ArgumentParser-generated help text. Includes all options/flags/argument
    /// the command declares; documentation tests scan this for `--help`,
    /// `--version`, `--read-only`, etc.
    public static var helpText: String {
        KittyCodeCommand.helpMessage(columns: 80)
    }

    // MARK: - Positional `path[:line[:col]]` parsing (custom, not in ArgumentParser)

    /// Parse a positional argument that may contain `:line` or `:line:col` suffixes.
    ///
    /// Windows-style paths (e.g. `C:\foo`) are handled by finding the last
    /// path-separator character before scanning colons, so the drive letter
    /// colon is never consumed.
    public static func parsePositional(_ raw: String) -> (path: String, line: Int?, column: Int?) {
        let lastSepIndex: String.Index =
            raw.lastIndex(where: { $0 == "/" || $0 == "\\" }) ?? raw.startIndex

        let filenamePortion = String(raw[lastSepIndex...])
        let components = filenamePortion.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        var trailingNumbers: [Int] = []
        for component in components.dropFirst().reversed() {
            if let n = Int(component), n > 0 {
                trailingNumbers.insert(n, at: 0)
            } else {
                break
            }
        }

        if trailingNumbers.count > 2 {
            trailingNumbers = Array(trailingNumbers.suffix(2))
        }
        let consumedComponents = trailingNumbers.count

        let line: Int? = trailingNumbers.count >= 1 ? trailingNumbers[0] : nil
        let column: Int? = trailingNumbers.count >= 2 ? trailingNumbers[1] : nil

        let pathString: String
        if consumedComponents == 0 {
            pathString = raw
        } else {
            let keepComponents = components.count - consumedComponents
            let reconstructedFilePart = components.prefix(keepComponents).joined(separator: ":")
            let dirPrefix: String
            if lastSepIndex == raw.startIndex {
                dirPrefix = ""
            } else {
                dirPrefix = String(raw[raw.startIndex..<lastSepIndex])
            }
            pathString = dirPrefix + reconstructedFilePart
        }

        let resolvedPath: String
        if pathString.hasPrefix("/") {
            resolvedPath = pathString
        } else if pathString.hasPrefix("~") {
            resolvedPath = Self.expandingTilde(in: pathString)
        } else {
            resolvedPath = FilePath(FileManager.default.currentDirectoryPath)
                .appending(pathString).string
        }

        return (resolvedPath, line, column)
    }

    /// Forwards to the shared `PathUtilities.expandingTilde` in `KittyEditor`
    /// (audit D3 extracted the editor library). Kept as a CLIArguments-namespace
    /// wrapper for callers that already reach for `CLIArguments.expandingTilde`.
    public static func expandingTilde(in path: String) -> String {
        PathUtilities.expandingTilde(in: path)
    }
}

// MARK: - ParsableCommand surface

/// Internal command type that ArgumentParser actually parses. Mapped back to
/// `CLIArguments.LaunchConfig` by `toLaunchConfig()`.
private struct KittyCodeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "kittycode",
        abstract: "A terminal code editor.",
        discussion: """
            Append :line or :line:col to the path to jump to a position
            (e.g. `kittycode src/main.swift:42:5`).
            """,
        version: CLIArguments.versionString
    )

    @Flag(name: [.customShort("R"), .long], help: "Open in read-only mode.")
    public var readOnly: Bool = false

    @Flag(name: .customLong("no-git"), help: "Disable git integration.")
    public var noGit: Bool = false

    @Flag(name: .customLong("no-syntax"), help: "Disable syntax highlighting.")
    public var noSyntax: Bool = false

    @Flag(name: .customLong("no-file-watcher"), help: "Disable file watching.")
    public var noFileWatcher: Bool = false

    @Flag(name: .customLong("no-symbols"), help: "Disable SF Symbol glyphs.")
    public var noSymbols: Bool = false

    @Flag(inversion: .prefixedNo, help: "Enable or disable line wrapping.")
    public var wrap: Bool?

    @Option(
        name: [.customShort("c"), .long],
        help: ArgumentHelp("Config file path.", valueName: "path"))
    public var config: String?

    @Option(help: ArgumentHelp("Keybinding mode: nano, vim, kittycode.", valueName: "mode"))
    public var mode: String?

    @Option(name: .long, help: ArgumentHelp("Tab display width.", valueName: "n"))
    public var tabSize: Int?

    @Option(name: .customLong("theme-fg"), help: ArgumentHelp("Editor foreground hex color.", valueName: "hex"))
    public var themeFg: String?

    @Argument(help: "File or directory to open (default: current directory).")
    public var path: String?

    public func validate() throws {
        if let mode {
            let allowed = ["nano", "vim", "kittycode"]
            guard allowed.contains(mode) else {
                throw ValidationError(
                    "unknown mode '\(mode)' — expected 'nano', 'vim', or 'kittycode'")
            }
        }
        if let tabSize, tabSize <= 0 {
            throw ValidationError("'--tab-size' must be a positive integer, got '\(tabSize)'")
        }
    }

    public func toLaunchConfig() -> CLIArguments.LaunchConfig {
        var rootPath = FileManager.default.currentDirectoryPath
        var initialFile: String?
        var initialLine: Int?
        var initialColumn: Int?

        if let raw = path {
            let (resolvedPath, line, column) = CLIArguments.parsePositional(raw)
            if Self.isDirectoryPath(resolvedPath) {
                rootPath = resolvedPath
            } else {
                let parent = FilePath(resolvedPath).removingLastComponent().string
                rootPath = parent.isEmpty ? FileManager.default.currentDirectoryPath : parent
                initialFile = resolvedPath
                initialLine = line
                initialColumn = column
            }
        }

        return CLIArguments.LaunchConfig(
            rootPath: rootPath,
            initialFile: initialFile,
            initialLine: initialLine,
            initialColumn: initialColumn,
            configPath: config,
            readOnly: readOnly,
            gitEnabled: noGit ? false : nil,
            syntaxEnabled: noSyntax ? false : nil,
            fileWatcherEnabled: noFileWatcher ? false : nil,
            symbolsEnabled: noSymbols ? false : nil,
            keybindingMode: mode,
            tabSize: tabSize,
            wrapLines: wrap,
            themeForeground: themeFg
        )
    }

    private static func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
