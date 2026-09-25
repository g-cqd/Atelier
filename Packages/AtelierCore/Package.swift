// swift-tools-version: 6.4

import PackageDescription

// aemi's strict tier on every target: Swift 6 language mode, warnings as errors, and the upcoming features that
// tighten existentials, isolation inference and import visibility.
let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

// The building blocks GitDiffViewer and KittyCode share. One package, one library product per target: an app
// links exactly the tiers it uses. Every target here is kernel-tier: structured concurrency only, clocks injected,
// aemi's runtime seams underneath.
let package = Package(
    name: "AtelierCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "AtelierSyntaxModel", targets: ["AtelierSyntaxModel"]),
        .library(name: "AtelierHighlighting", targets: ["AtelierHighlighting"]),
        .library(name: "AtelierDiff", targets: ["AtelierDiff"]),
        .library(name: "AtelierLexers", targets: ["AtelierLexers"]),
        .library(name: "AtelierSwiftSyntax", targets: ["AtelierSwiftSyntax"]),
        .library(name: "AtelierProcess", targets: ["AtelierProcess"]),
        .library(name: "AtelierGit", targets: ["AtelierGit"]),
        .library(name: "AtelierTestSupport", targets: ["AtelierTestSupport"]),
        .library(name: "AtelierSources", targets: ["AtelierSources"]),
        .library(name: "AtelierText", targets: ["AtelierText"]),
        .library(name: "AtelierGrammar", targets: ["AtelierGrammar"]),
        .library(name: "AtelierParser", targets: ["AtelierParser"]),
        .library(name: "AtelierQuery", targets: ["AtelierQuery"]),
        .library(name: "AtelierScanners", targets: ["AtelierScanners"]),
        .library(name: "AtelierGrammarCorpus", targets: ["AtelierGrammarCorpus"]),
        .library(name: "AtelierTheme", targets: ["AtelierTheme"]),
        .library(name: "AtelierFileTree", targets: ["AtelierFileTree"]),
        .library(name: "AtelierSearch", targets: ["AtelierSearch"]),
        .library(name: "AtelierDiagnostics", targets: ["AtelierDiagnostics"]),
        .library(name: "AtelierLSP", targets: ["AtelierLSP"]),
        .library(name: "AtelierDocIndex", targets: ["AtelierDocIndex"])
    ],
    dependencies: [
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "85065dc105c2f52cac1688242353a5c7eb0e45ce"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        // Pinned to the tip of AemiJSON's main (`JSON.withRawJSONBytes`, JSON5 escapes), which pins the same aemi
        // revision; the private mirror needs the g-cqd SSH credentials. Iterate locally with
        // `.package(path: "../../../AemiJSON")`.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "6b8e5b9fb14b6c835d0dca13ba15f5bb1f3831de")
    ],
    targets: [
        // The vocabulary highlighting is expressed in: languages, and later roles and tokens.
        .target(name: "AtelierSyntaxModel", swiftSettings: strict),
        // The tier job (PERF-11): the highlight tier protocol, and every tier of a text run at once, each on its own,
        // caller-driven. Each tier lives with its engine; the apps compose them.
        .target(name: "AtelierHighlighting", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
        // Line and intraline diffing, moved blocks, hunk layout and unified patches. Pure value code.
        .target(
            name: "AtelierDiff",
            dependencies: ["AtelierSyntaxModel", .product(name: "AemiKernel", package: "aemi")],
            swiftSettings: strict
        ),
        // Hand-written scanners over borrowed UTF-8 bytes for the lexical tier; a scan allocates only its token array.
        // They also scan a line at a time from its entry state, over AtelierText's line sources (P1a).
        .target(
            name: "AtelierLexers", dependencies: ["AtelierHighlighting", "AtelierSyntaxModel", "AtelierText"],
            swiftSettings: strict),
        // swift-syntax support: the syntax tier's token provider, the syntactic colour tier over SwiftIDEUtils'
        // classification, and the deep stack every swift-syntax parse and tree walk runs on.
        .target(
            name: "AtelierSwiftSyntax",
            dependencies: [
                "AtelierDiff", "AtelierHighlighting", "AtelierLexers", "AtelierSyntaxModel",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftIDEUtils", package: "swift-syntax")
            ],
            swiftSettings: strict
        ),
        // Subprocesses: one blocking job per run on aemi's pool, temp-file input and errors, clock-driven timeouts;
        // plus a long-lived bidirectional session over swift-subprocess for servers that speak over stdio.
        .target(
            name: "AtelierProcess",
            dependencies: [
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "Subprocess", package: "swift-subprocess")
            ],
            swiftSettings: strict
        ),
        // Static-analysis tools as values: discovery on disk, argv builders, SARIF and xcode-format parsing, and an
        // engine that runs each tool as one cancellable, cached, off-main job.
        .target(
            name: "AtelierDiagnostics",
            dependencies: [
                "AtelierProcess", .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON")
            ],
            swiftSettings: strict
        ),
        // A minimal Language Server Protocol client: base-protocol framing, JSON-RPC, and a sourcekit-lsp session
        // for hover documentation.
        .target(
            name: "AtelierLSP",
            dependencies: [
                "AtelierProcess", "AtelierSyntaxModel",
                .product(name: "AemiJSON", package: "AemiJSON")
            ],
            swiftSettings: strict
        ),
        // Documentation from source alone: doc comments indexed over swift-syntax trees, and the identifier under a
        // position, for hover content that needs no build context. Files parse side by side through AemiRuntime.
        .target(
            name: "AtelierDocIndex",
            dependencies: [
                "AtelierSwiftSyntax", "AtelierSyntaxModel",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict
        ),
        // A git client over AtelierProcess: commands as methods, output parsed by pure functions in GitParsers.
        .target(
            name: "AtelierGit",
            dependencies: ["AtelierProcess", .product(name: "AemiRuntime", package: "aemi")],
            swiftSettings: strict
        ),
        // What a comparison reads from: files, folders, git refs and patches, each behind one provider, plus the
        // blob hashing that decides whether two files differ.
        .target(
            name: "AtelierSources",
            dependencies: [
                "AtelierGit", "AtelierProcess", "AtelierDiff", "AtelierSyntaxModel",
                .product(name: "AemiIO", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict
        ),
        // Text storage: a UTF-8 rope with a line index, cursors, selections, mutations and display metrics.
        .target(name: "AtelierText", swiftSettings: strict),
        // File trees: a lazily scanned directory tree with secure paths, visibility rules and git statuses, and a
        // tree built from relative paths with chain compaction, as a comparison's explorer shows it.
        .target(
            name: "AtelierFileTree",
            dependencies: ["AtelierGit", "AtelierProcess", .product(name: "AemiRuntime", package: "aemi")],
            swiftSettings: strict
        ),
        // Workspace search: file enumeration, literal and regex matching over files read on the blocking pool, and
        // replacement templates.
        .target(
            name: "AtelierSearch",
            dependencies: [
                .product(name: "AemiKernels", package: "aemi"), .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiIO", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict
        ),
        // tree-sitter grammar.json loading and LR/lex table compilation. Reads grammar.json with AemiJSON's
        // Foundation-free engine; the Codable layer is not needed.
        .target(
            name: "AtelierGrammar", dependencies: [.product(name: "AemiJSONCore", package: "AemiJSON")],
            swiftSettings: strict),
        // The GLR parser over compiled tables.
        .target(name: "AtelierParser", dependencies: ["AtelierGrammar"], swiftSettings: strict),
        // tree-sitter .scm query parsing and matching over syntax trees.
        .target(name: "AtelierQuery", dependencies: ["AtelierParser"], swiftSettings: strict),
        // External scanners ported from each grammar's tree-sitter scanner.c, one file per language.
        .target(name: "AtelierScanners", dependencies: ["AtelierParser"], swiftSettings: strict),
        // The bundled tree-sitter grammars and `languages.json`, and the loading of their artifacts: the grammar
        // registry, the compiled-table disk cache and the per-language artifacts cache.
        .target(
            name: "AtelierGrammarCorpus",
            dependencies: [
                "AtelierGrammar", "AtelierParser", "AtelierQuery", "AtelierScanners", "AtelierSyntaxModel",
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiKernel", package: "aemi")
            ],
            resources: [.copy("Grammars")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "AtelierGrammarCorpusTests",
            dependencies: [
                "AtelierGrammarCorpus", "AtelierGrammar", "AtelierParser",
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "AtelierDiffTests", dependencies: ["AtelierDiff", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strict),
        .testTarget(name: "AtelierSyntaxModelTests", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
        .testTarget(
            name: "AtelierHighlightingTests",
            dependencies: [
                "AtelierHighlighting", "AtelierLexers", "AtelierSwiftSyntax", "AtelierSyntaxModel",
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "AtelierFileTreeTests",
            dependencies: [
                "AtelierFileTree", .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "AtelierSearchTests",
            dependencies: [
                "AtelierSearch", .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict),
        // Themes as values keyed by highlight role, with Xcode theme import; the apps bridge to their colour types.
        .target(name: "AtelierTheme", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
        .testTarget(
            name: "AtelierThemeTests", dependencies: ["AtelierTheme", "AtelierSyntaxModel"], swiftSettings: strict),
        .testTarget(name: "AtelierTextTests", dependencies: ["AtelierText"], swiftSettings: strict),
        .testTarget(name: "AtelierGrammarTests", dependencies: ["AtelierGrammar"], swiftSettings: strict),
        .testTarget(
            name: "AtelierParserTests", dependencies: ["AtelierParser", "AtelierScanners"], swiftSettings: strict),
        .testTarget(name: "AtelierQueryTests", dependencies: ["AtelierQuery"], swiftSettings: strict),
        .testTarget(
            name: "AtelierScannersTests", dependencies: ["AtelierScanners", "AtelierParser"], swiftSettings: strict),
        .testTarget(
            name: "AtelierSourcesTests",
            dependencies: [
                "AtelierSources", "AtelierGit", "AtelierProcess", "AtelierSyntaxModel", "AtelierTestSupport",
                .product(name: "AemiIO", package: "aemi"), .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict
        ),
        // Test doubles both apps' suites and the core's share; family-neutral so either test kit can sit next to it.
        .target(name: "AtelierTestSupport", dependencies: ["AtelierProcess"], swiftSettings: strict),
        .testTarget(
            name: "AtelierGitTests",
            dependencies: [
                "AtelierGit", "AtelierProcess", "AtelierTestSupport", .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "AtelierProcessTests",
            dependencies: [
                "AtelierProcess", .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "AtelierLexersTests",
            dependencies: [
                "AtelierLexers", "AtelierSyntaxModel", "AtelierText", .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "AtelierSwiftSyntaxTests",
            dependencies: [
                "AtelierSwiftSyntax", "AtelierDiff", "AtelierLexers", "AtelierSyntaxModel",
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "AtelierDiagnosticsTests",
            dependencies: [
                "AtelierDiagnostics", "AtelierProcess", "AtelierTestSupport",
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "AtelierLSPTests",
            dependencies: [
                "AtelierLSP", "AtelierProcess", .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "AtelierDocIndexTests",
            dependencies: [
                "AtelierDocIndex", "AtelierSwiftSyntax", "AtelierSyntaxModel",
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict)
    ]
)
