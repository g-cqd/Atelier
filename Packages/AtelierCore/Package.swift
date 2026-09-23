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
        .library(name: "AtelierTheme", targets: ["AtelierTheme"]),
        .library(name: "AtelierFileTree", targets: ["AtelierFileTree"]),
        .library(name: "AtelierSearch", targets: ["AtelierSearch"]),
        .library(name: "AtelierDiagnostics", targets: ["AtelierDiagnostics"]),
        .library(name: "AtelierLSP", targets: ["AtelierLSP"]),
        .library(name: "AtelierDocIndex", targets: ["AtelierDocIndex"])
    ],
    dependencies: [
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "739d982e95db75eb1e6565c79c42c705dbae247f"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        // Pinned to the feature/raw-subtree-bytes revision for `JSON.withRawJSONBytes`; the private mirror needs the
        // g-cqd SSH credentials. Iterate locally with `.package(path: "../../../AemiJSON")`.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "efb0a35746e17db0cc519bc8f6fa23887f7105aa")
    ],
    targets: [
        // The vocabulary highlighting is expressed in: languages, and later roles and tokens.
        .target(name: "AtelierSyntaxModel", swiftSettings: strict),
        // Line and intraline diffing, moved blocks, hunk layout and unified patches. Pure value code.
        .target(
            name: "AtelierDiff",
            dependencies: ["AtelierSyntaxModel", .product(name: "AemiKernel", package: "aemi")],
            swiftSettings: strict
        ),
        // Hand-written, allocation-free scanners over UTF-16 units for the lexical tier.
        .target(name: "AtelierLexers", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
        // The swift-syntax backed token provider for the syntax tier; the one target that links swift-syntax.
        .target(
            name: "AtelierSwiftSyntax",
            dependencies: [
                "AtelierDiff", "AtelierLexers", "AtelierSyntaxModel",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
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
                "AtelierSyntaxModel",
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
        .testTarget(
            name: "AtelierDiffTests", dependencies: ["AtelierDiff", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strict),
        .testTarget(name: "AtelierSyntaxModelTests", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
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
        .testTarget(name: "AtelierParserTests", dependencies: ["AtelierParser"], swiftSettings: strict),
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
            dependencies: ["AtelierLexers", "AtelierSyntaxModel", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strict),
        .testTarget(
            name: "AtelierSwiftSyntaxTests", dependencies: ["AtelierSwiftSyntax", "AtelierDiff", "AtelierSyntaxModel"],
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
            name: "AtelierDocIndexTests", dependencies: ["AtelierDocIndex", "AtelierSyntaxModel"],
            swiftSettings: strict)
    ]
)
