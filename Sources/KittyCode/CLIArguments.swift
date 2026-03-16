import Foundation

/// Parses `CommandLine.arguments` into a structured launch action.
struct CLIArguments: Sendable {
    enum Action: Sendable {
        case run(LaunchConfig)
        case printVersion
        case printHelp
    }

    struct LaunchConfig: Sendable {
        var rootPath: String
        var initialFile: String?
        var initialLine: Int?
        var initialColumn: Int?
        var configPath: String?
        var readOnly: Bool
        var gitEnabled: Bool?
        var syntaxEnabled: Bool?
        var fileWatcherEnabled: Bool?
        var symbolsEnabled: Bool?
        var keybindingMode: String?
        var tabSize: Int?
        var wrapLines: Bool?
        var themeForeground: String?
    }

    static func parse(_ args: [String] = CommandLine.arguments) -> Action {
        // Skip argv[0] (executable name).
        var tokens = Array(args.dropFirst())

        var positional: String?
        var configPath: String?
        var readOnly = false
        var gitEnabled: Bool?
        var syntaxEnabled: Bool?
        var fileWatcherEnabled: Bool?
        var symbolsEnabled: Bool?
        var keybindingMode: String?
        var tabSize: Int?
        var wrapLines: Bool?
        var themeForeground: String?

        while !tokens.isEmpty {
            let token = tokens.removeFirst()

            switch token {
            case "--help", "-h":
                return .printHelp

            case "--version", "-v":
                return .printVersion

            case "--read-only", "-R":
                readOnly = true

            case "--no-git":
                gitEnabled = false

            case "--no-syntax":
                syntaxEnabled = false

            case "--no-file-watcher":
                fileWatcherEnabled = false

            case "--no-symbols":
                symbolsEnabled = false

            case "--wrap":
                wrapLines = true

            case "--no-wrap":
                wrapLines = false

            case "--config", "-c":
                guard !tokens.isEmpty else {
                    writeStderr("error: '\(token)' requires a PATH argument")
                    exit(1)
                }
                configPath = tokens.removeFirst()

            case "--mode":
                guard !tokens.isEmpty else {
                    writeStderr("error: '--mode' requires a MODE argument (nano, vim, kittycode)")
                    exit(1)
                }
                let value = tokens.removeFirst()
                guard value == "nano" || value == "vim" || value == "kittycode" else {
                    writeStderr(
                        "error: unknown mode '\(value)' — expected 'nano', 'vim', or 'kittycode'")
                    exit(1)
                }
                keybindingMode = value

            case "--tab-size":
                guard !tokens.isEmpty else {
                    writeStderr("error: '--tab-size' requires a numeric argument")
                    exit(1)
                }
                let raw = tokens.removeFirst()
                guard let n = Int(raw), n > 0 else {
                    writeStderr("error: '--tab-size' must be a positive integer, got '\(raw)'")
                    exit(1)
                }
                tabSize = n

            case "--theme-fg":
                guard !tokens.isEmpty else {
                    writeStderr("error: '--theme-fg' requires a hex color argument (e.g. c9d1d9)")
                    exit(1)
                }
                themeForeground = tokens.removeFirst()

            default:
                if token.hasPrefix("-") {
                    writeStderr("error: unknown option '\(token)' — run with --help for usage")
                    exit(1)
                }
                if positional != nil {
                    writeStderr(
                        "error: unexpected argument '\(token)' — only one path argument is accepted"
                    )
                    exit(1)
                }
                positional = token
            }
        }

        let config = buildLaunchConfig(
            positional: positional,
            configPath: configPath,
            readOnly: readOnly,
            gitEnabled: gitEnabled,
            syntaxEnabled: syntaxEnabled,
            fileWatcherEnabled: fileWatcherEnabled,
            symbolsEnabled: symbolsEnabled,
            keybindingMode: keybindingMode,
            tabSize: tabSize,
            wrapLines: wrapLines,
            themeForeground: themeForeground
        )

        return .run(config)
    }

    // MARK: - Help / version text

    static let versionString = "KittyCode 0.1.0"

    static let helpText = """
        KittyCode \u{2014} A terminal code editor

        USAGE:
            kittycode [OPTIONS] [path[:line[:col]]]

        ARGUMENTS:
            [path]              File or directory to open (default: current directory)
                                Append :line or :line:col to jump to a position

        OPTIONS:
            -h, --help          Show this help message
            -v, --version       Show version
            -R, --read-only     Open in read-only mode
            -c, --config PATH   Config file path (default: ~/.kittycode.json)
            --mode MODE         Keybinding mode: nano, vim, kittycode
            --tab-size N        Tab display width
            --wrap              Enable line wrapping
            --no-wrap           Disable line wrapping
            --no-git            Disable git integration
            --no-syntax         Disable syntax highlighting
            --no-file-watcher   Disable file watching
            --no-symbols        Disable SF Symbol glyphs
        """

    // MARK: - Private helpers

    private static func buildLaunchConfig(
        positional: String?,
        configPath: String?,
        readOnly: Bool,
        gitEnabled: Bool?,
        syntaxEnabled: Bool?,
        fileWatcherEnabled: Bool?,
        symbolsEnabled: Bool?,
        keybindingMode: String?,
        tabSize: Int?,
        wrapLines: Bool?,
        themeForeground: String?
    ) -> LaunchConfig {
        var rootPath = FileManager.default.currentDirectoryPath
        var initialFile: String?
        var initialLine: Int?
        var initialColumn: Int?

        if let raw = positional {
            let (resolvedPath, line, column) = parsePositional(raw)
            let isDirectory = isDirectoryPath(resolvedPath)

            if isDirectory {
                rootPath = resolvedPath
            } else {
                // It's a file — use its parent as rootPath
                let parent = (resolvedPath as NSString).deletingLastPathComponent
                rootPath = parent.isEmpty ? FileManager.default.currentDirectoryPath : parent
                initialFile = resolvedPath
                initialLine = line
                initialColumn = column
            }
        }

        return LaunchConfig(
            rootPath: rootPath,
            initialFile: initialFile,
            initialLine: initialLine,
            initialColumn: initialColumn,
            configPath: configPath,
            readOnly: readOnly,
            gitEnabled: gitEnabled,
            syntaxEnabled: syntaxEnabled,
            fileWatcherEnabled: fileWatcherEnabled,
            symbolsEnabled: symbolsEnabled,
            keybindingMode: keybindingMode,
            tabSize: tabSize,
            wrapLines: wrapLines,
            themeForeground: themeForeground
        )
    }

    /// Parse a positional argument that may contain `:line` or `:line:col` suffixes.
    ///
    /// Windows-style paths (e.g. `C:\foo`) are handled by finding the last path-separator
    /// character before scanning colons, so the drive letter colon is never consumed.
    static func parsePositional(_ raw: String) -> (path: String, line: Int?, column: Int?) {
        // We only inspect colons that appear after the last path separator, so that
        // drive-letter colons (C:\...) and colons in directory names are not consumed.
        let lastSepIndex: String.Index =
            raw.lastIndex(where: { $0 == "/" || $0 == "\\" }) ?? raw.startIndex

        // Split the filename-and-suffix portion on ":" to find trailing numeric segments.
        let filenamePortion = String(raw[lastSepIndex...])
        let components = filenamePortion.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        // Walk backward through components after [0] (the filename part) collecting
        // contiguous positive integers as line/col suffixes.
        var trailingNumbers: [Int] = []
        for component in components.dropFirst().reversed() {
            if let n = Int(component), n > 0 {
                trailingNumbers.insert(n, at: 0)
            } else {
                break
            }
        }

        // At most 2 trailing numeric suffixes are significant (line, col).
        if trailingNumbers.count > 2 {
            trailingNumbers = Array(trailingNumbers.suffix(2))
        }
        let consumedComponents = trailingNumbers.count

        let line: Int? = trailingNumbers.count >= 1 ? trailingNumbers[0] : nil
        let column: Int? = trailingNumbers.count >= 2 ? trailingNumbers[1] : nil

        // Reconstruct the raw path by stripping the consumed colon-suffixes.
        // The prefix before lastSepIndex is unchanged; we rejoin only the filename components.
        let pathString: String
        if consumedComponents == 0 {
            pathString = raw
        } else {
            // Keep the directory prefix and the filename component, drop the numeric suffixes.
            let keepComponents = components.count - consumedComponents
            let reconstructedFilePart = components.prefix(keepComponents).joined(separator: ":")
            // The directory prefix is everything in `raw` before `lastSepIndex`.
            let dirPrefix: String
            if lastSepIndex == raw.startIndex {
                // No separator found — raw is just a filename, no directory prefix.
                dirPrefix = ""
            } else {
                dirPrefix = String(raw[raw.startIndex..<lastSepIndex])
            }
            pathString = dirPrefix + reconstructedFilePart
        }

        // Resolve to absolute path if not already absolute.
        let resolvedPath: String
        if pathString.hasPrefix("/") || pathString.hasPrefix("~") {
            resolvedPath = (pathString as NSString).expandingTildeInPath
        } else {
            resolvedPath = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(pathString)
        }

        return (resolvedPath, line, column)
    }

    private static func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
