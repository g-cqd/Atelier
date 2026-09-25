public import AtelierProcess
public import AtelierSyntaxModel
public import Foundation

/// A language server as data: how to find and run it, the languages it serves, where its workspace root is, and how
/// long its sessions wait. ``LanguageServerSession`` runs any of them alike.
public struct LanguageServerDescriptor: Sendable, Equatable, Identifiable {
    /// How long a server's sessions wait, and how many documents and restarts they allow.
    public struct SessionTuning: Sendable, Equatable {
        /// How long a session stays connected with no request before it shuts down.
        public var idleShutdown: Duration
        /// The cap on the `initialize` handshake, which a server that loads a runtime first needs longer for.
        public var initializeTimeout: Duration
        /// The cap on any request after the handshake.
        public var requestTimeout: Duration
        /// How many failed connection attempts are retried before a session gives up for good.
        public var maximumRestarts: Int
        /// How many documents stay open on the server at once.
        public var openDocumentLimit: Int

        public init(
            idleShutdown: Duration = .seconds(180), initializeTimeout: Duration = .seconds(2),
            requestTimeout: Duration = .seconds(2), maximumRestarts: Int = 2, openDocumentLimit: Int = 32
        ) {
            self.idleShutdown = idleShutdown
            self.initializeTimeout = initializeTimeout
            self.requestTimeout = requestTimeout
            self.maximumRestarts = maximumRestarts
            self.openDocumentLimit = openDocumentLimit
        }
    }

    /// The server's stable identifier, under which settings store its location, as `sourcekit-lsp`.
    public let id: String
    /// The server's name in the user interface.
    public let displayName: String
    /// The executable's names, most preferred first.
    public let executableNames: [String]
    /// The arguments the server runs with, such as `--stdio`.
    public let arguments: [String]
    /// The languages whose documents the server answers for.
    public let languages: Set<Language>
    /// File names that mark a workspace root, strongest first: the nearest directory holding the first marker found
    /// is the root. Empty keeps the root the caller starts from.
    public let rootMarkers: [String]
    /// The server's own `initializationOptions`; nil sends none.
    public let initializationOptions: JSONValue?
    /// The upper-case name an app prefixes to form the environment variable that overrides the executable's path, as
    /// `SOURCEKIT_LSP` in `GDV_SOURCEKIT_LSP`.
    public let environmentName: String
    /// Whether the active Xcode toolchain is asked for the executable.
    public let searchesToolchain: Bool
    /// Directories under the user's home the server installs to, searched after the usual install locations.
    public let homeRelativeDirectories: [String]
    public let tuning: SessionTuning
    /// Whether the server answers sourcekit-lsp's `textDocument/symbolInfo`, from which a system symbol's page in
    /// Apple's developer documentation is found.
    public let resolvesDocumentationPages: Bool
    /// The runtime the server's executable starts through its `#!/usr/bin/env` line, as `node`; nil for a native one.
    public let runtimeExecutableName: String?

    public init(
        id: String, displayName: String, executableNames: [String], arguments: [String] = [],
        languages: Set<Language>, rootMarkers: [String] = [], initializationOptions: JSONValue? = nil,
        environmentName: String, searchesToolchain: Bool = false, homeRelativeDirectories: [String] = [],
        tuning: SessionTuning = SessionTuning(), resolvesDocumentationPages: Bool = false,
        runtimeExecutableName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.executableNames = executableNames
        self.arguments = arguments
        self.languages = languages
        self.rootMarkers = rootMarkers
        self.initializationOptions = initializationOptions
        self.environmentName = environmentName
        self.searchesToolchain = searchesToolchain
        self.homeRelativeDirectories = homeRelativeDirectories
        self.tuning = tuning
        self.resolvesDocumentationPages = resolvesDocumentationPages
        self.runtimeExecutableName = runtimeExecutableName
    }

    /// The query that finds the server's executable: `customPath` first, after the environment variable
    /// `overridePrefix` + ``environmentName`` when a prefix is given.
    public func executableQuery(customPath: String?, overridePrefix: String?) -> ExecutableQuery {
        ExecutableQuery(
            names: executableNames, overrideVariable: overridePrefix.map { $0 + environmentName },
            customPath: customPath, searchesToolchain: searchesToolchain,
            homeRelativeDirectories: homeRelativeDirectories)
    }

    /// The server's executable as `locator` finds it for ``executableQuery(customPath:overridePrefix:)``; nil when it
    /// is not installed.
    public func locate(
        using locator: any ExecutableLocating, customPath: String?, overridePrefix: String?
    ) async -> URL? {
        await locator.locateExecutable(executableQuery(customPath: customPath, overridePrefix: overridePrefix))
    }

    /// The environment a session of the server runs with: nil, the app's own, for a server without a runtime;
    /// otherwise `base` with the runtime's directory first on its `PATH`, so that `#!/usr/bin/env node` finds it in an
    /// app launched from the Finder, whose `PATH` holds only the system's directories. The runtime is looked for
    /// next to `serverExecutable` first, where a version manager installs both, then as `locator` finds it; nil when
    /// neither finds it.
    public func sessionEnvironment(
        serverExecutable: URL, locator: any ExecutableLocating, base: [String: String]
    ) async -> [String: String]? {
        guard let runtimeExecutableName else { return nil }
        let sibling = serverExecutable.deletingLastPathComponent().appending(path: runtimeExecutableName)
        let runtime: URL
        if FileManager.default.isExecutableFile(atPath: sibling.path(percentEncoded: false)) {
            runtime = sibling
        } else if let located = await locator.locateExecutable(
            ExecutableQuery(names: [runtimeExecutableName], homeRelativeDirectories: homeRelativeDirectories))
        {
            runtime = located
        } else {
            return nil
        }
        let directory = runtime.deletingLastPathComponent().path(percentEncoded: false)
        let trimmed = directory.count > 1 && directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        let rest = (base["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0 != trimmed }
        var environment = base
        environment["PATH"] = ([trimmed] + rest).joined(separator: ":")
        return environment
    }

    /// The language ID a document at `url` carries to the server: the React dialects' own IDs for `.tsx` and `.jsx`,
    /// which typescript-language-server parses as JSX; Objective-C++'s for `.mm`; for a `.h` header, which C, C++ and
    /// Objective-C all use, the one its `content` reads as (``headerLanguageID(content:)``); and
    /// ``Language/lspLanguageID`` otherwise.
    public static func languageID(forDocumentAt url: URL, content: String = "") -> String {
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
            case "tsx": return "typescriptreact"
            case "jsx": return "javascriptreact"
            case "mm": return objectiveCppLanguageID
            case "h": return headerLanguageID(content: content)
            default: return Language(fileExtension: fileExtension).lspLanguageID
        }
    }

    /// The specification's language ID for Objective-C++, which ``Language`` counts as Objective-C.
    static let objectiveCppLanguageID = "objective-cpp"

    /// The language a `.h` header's `content` is written in, as its language ID: Objective-C when a line starts with
    /// one of its directives (`@interface`, `@protocol`, `#import`, …), Objective-C++ when C++ shows too, C++ when a
    /// line starts with `namespace`, `template`, `class` or an access label, or uses `std::`, and C otherwise, which an
    /// empty header is. Comment lines, and lines inside a `#if` on `__cplusplus`, where a C header wraps its
    /// `extern "C"`, count for nothing.
    /// - Complexity: O(n) in the length of `content`, one pass over its lines.
    public static func headerLanguageID(content: String) -> String {
        var isObjectiveC = false
        var isCpp = false
        var inBlockComment = false
        // The depth of the conditional blocks from the first `#if` on `__cplusplus`; zero outside one.
        var cplusplusDepth = 0
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = rawLine.drop { $0 == " " || $0 == "\t" }
            if inBlockComment {
                guard let end = line.firstRange(of: "*/") else { continue }
                inBlockComment = false
                line = line[end.upperBound...].drop { $0 == " " || $0 == "\t" }
            }
            if line.hasPrefix("//") { continue }
            if line.hasPrefix("/*"), line.firstRange(of: "*/") == nil {
                inBlockComment = true
                continue
            }
            if line.hasPrefix("#") {
                let directive = line.dropFirst().drop { $0 == " " || $0 == "\t" }
                if cplusplusDepth > 0 {
                    if directive.hasPrefix("if") {
                        cplusplusDepth += 1
                    } else if directive.hasPrefix("endif") {
                        cplusplusDepth -= 1
                    }
                    continue
                }
                if directive.hasPrefix("if"), directive.contains("__cplusplus") {
                    cplusplusDepth = 1
                    continue
                }
                if directive.hasPrefix("import") { isObjectiveC = true }
                continue
            }
            guard cplusplusDepth == 0 else { continue }
            if objectiveCLinePrefixes.contains(where: { line.hasPrefix($0) }) {
                isObjectiveC = true
            } else if cppLinePrefixes.contains(where: { line.hasPrefix($0) }) || line.contains("std::") {
                isCpp = true
            }
        }
        switch (isObjectiveC, isCpp) {
            case (true, true): return objectiveCppLanguageID
            case (true, false): return Language.objectiveC.lspLanguageID
            case (false, true): return Language.cpp.lspLanguageID
            case (false, false): return Language.c.lspLanguageID
        }
    }

    /// The starts of lines only Objective-C writes.
    private static let objectiveCLinePrefixes = [
        "@interface", "@protocol", "@implementation", "@class", "@property", "@end", "@import ",
        "NS_ASSUME_NONNULL_BEGIN"
    ]
    /// The starts of lines only C++ writes.
    private static let cppLinePrefixes = [
        "namespace ", "namespace{", "template <", "template<", "class ", "enum class ", "public:", "private:",
        "protected:", "using namespace "
    ]
}

// MARK: - The servers

extension LanguageServerDescriptor {
    /// sourcekit-lsp, for Swift, from the toolchain; its hover sessions skip background indexing, which builds the
    /// project. Its root is the one the caller starts from, the repository's, as before the other servers came.
    public static let sourceKitLSP = LanguageServerDescriptor(
        id: "sourcekit-lsp", displayName: "sourcekit-lsp", executableNames: ["sourcekit-lsp"], languages: [.swift],
        initializationOptions: .object(["backgroundIndexing": .bool(false)]), environmentName: "SOURCEKIT_LSP",
        searchesToolchain: true, resolvesDocumentationPages: true)

    /// Where the language toolchains install servers under the user's home, beyond the usual locations: npm's
    /// global prefix as its documentation sets it up, cargo's and `go install`'s.
    public static let userInstallDirectories = [".npm-global/bin", ".cargo/bin", "go/bin"]

    /// typescript-language-server over stdio, for TypeScript and JavaScript; the nearest `tsconfig.json` wins over a
    /// nearer `package.json`.
    public static let typeScriptLanguageServer = LanguageServerDescriptor(
        id: "typescript-language-server", displayName: "typescript-language-server",
        executableNames: ["typescript-language-server"], arguments: ["--stdio"], languages: [.typescript, .javascript],
        rootMarkers: ["tsconfig.json", "jsconfig.json", "package.json"], environmentName: "TYPESCRIPT_LANGUAGE_SERVER",
        homeRelativeDirectories: userInstallDirectories, tuning: SessionTuning(initializeTimeout: .seconds(10)),
        runtimeExecutableName: "node")

    /// gopls, for Go; a `go.work` anywhere above wins over a nearer `go.mod`.
    public static let gopls = LanguageServerDescriptor(
        id: "gopls", displayName: "gopls", executableNames: ["gopls"], languages: [.go],
        rootMarkers: ["go.work", "go.mod"], environmentName: "GOPLS", homeRelativeDirectories: userInstallDirectories,
        tuning: SessionTuning(initializeTimeout: .seconds(10)))

    /// clangd, for C, C++ and Objective-C, from the toolchain; its hover sessions skip background indexing, which
    /// indexes the whole project. The nearest `compile_commands.json` wins over a nearer `.clangd`; without either, the
    /// root is the one the caller starts from, and clangd answers from its fallback flags, without the project's
    /// include paths and definitions.
    public static let clangd = LanguageServerDescriptor(
        id: "clangd", displayName: "clangd", executableNames: ["clangd"], arguments: ["--background-index=false"],
        languages: [.c, .cpp, .objectiveC], rootMarkers: ["compile_commands.json", ".clangd"],
        environmentName: "CLANGD", searchesToolchain: true, tuning: SessionTuning(initializeTimeout: .seconds(10)))

    /// rust-analyzer, for Rust, from rustup's `~/.cargo/bin`, rooted at the nearest `Cargo.toml`. Its hover sessions
    /// neither build the project's build scripts and procedural macros nor prime the caches of every crate, which
    /// compile and index the project and its dependencies; `cargo check` never runs, since a hover saves nothing.
    public static let rustAnalyzer = LanguageServerDescriptor(
        id: "rust-analyzer", displayName: "rust-analyzer", executableNames: ["rust-analyzer"], languages: [.rust],
        rootMarkers: ["Cargo.toml"],
        initializationOptions: .object([
            "cargo": .object(["buildScripts": .object(["enable": .bool(false)])]),
            "procMacro": .object(["enable": .bool(false)]),
            "cachePriming": .object(["enable": .bool(false)]),
            "checkOnSave": .bool(false)
        ]),
        environmentName: "RUST_ANALYZER", homeRelativeDirectories: userInstallDirectories,
        tuning: SessionTuning(initializeTimeout: .seconds(10)))

    /// basedpyright's language server over stdio, for Python; a `pyrightconfig.json` anywhere above wins over a
    /// nearer `pyproject.toml`. pip, pipx and uv install it in `~/.local/bin`, with the Node.js it runs on.
    public static let basedPyright = LanguageServerDescriptor(
        id: "basedpyright", displayName: "basedpyright", executableNames: ["basedpyright-langserver"],
        arguments: ["--stdio"], languages: [.python], rootMarkers: ["pyrightconfig.json", "pyproject.toml"],
        environmentName: "BASEDPYRIGHT", homeRelativeDirectories: userInstallDirectories + [".local/bin"],
        tuning: SessionTuning(initializeTimeout: .seconds(10)))

    /// Every server hover knows, in no particular order: each language has one server at most.
    public static let all: [LanguageServerDescriptor] = [
        sourceKitLSP, typeScriptLanguageServer, gopls, clangd, rustAnalyzer, basedPyright
    ]

    /// The server among `servers` that answers for `language`; nil when none does.
    public static func serving(
        _ language: Language, among servers: [LanguageServerDescriptor] = all
    ) -> LanguageServerDescriptor? {
        servers.first { $0.languages.contains(language) }
    }
}

// MARK: - Sessions

extension LanguageServerSession.Configuration {
    /// A session of `descriptor`'s server, run from `serverExecutable` with `environment`, nil for the app's own, and
    /// with the server's arguments, options and tuning.
    public init(
        descriptor: LanguageServerDescriptor, serverExecutable: URL, workspaceRoot: URL,
        environment: [String: String]? = nil
    ) {
        self.init(
            serverExecutable: serverExecutable, serverArguments: descriptor.arguments, workspaceRoot: workspaceRoot,
            idleShutdown: descriptor.tuning.idleShutdown, initializeTimeout: descriptor.tuning.initializeTimeout,
            requestTimeout: descriptor.tuning.requestTimeout, maximumRestarts: descriptor.tuning.maximumRestarts,
            openDocumentLimit: descriptor.tuning.openDocumentLimit,
            initializationOptions: descriptor.initializationOptions, environment: environment)
    }
}
