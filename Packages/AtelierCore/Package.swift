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
        .library(name: "AtelierTheme", targets: ["AtelierTheme"])
    ],
    dependencies: [
        .package(url: "https://github.com/Aemi-Studio/aemi.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0")
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
        // Subprocesses: one blocking job per run on aemi's pool, temp-file input and errors, clock-driven timeouts.
        .target(
            name: "AtelierProcess",
            dependencies: [.product(name: "AemiRuntime", package: "aemi")],
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
        // tree-sitter grammar.json loading and LR/lex table compilation.
        .target(name: "AtelierGrammar", swiftSettings: strict),
        // The GLR parser over compiled tables.
        .target(name: "AtelierParser", dependencies: ["AtelierGrammar"], swiftSettings: strict),
        // tree-sitter .scm query parsing and matching over syntax trees.
        .target(name: "AtelierQuery", dependencies: ["AtelierParser"], swiftSettings: strict),
        .testTarget(
            name: "AtelierDiffTests", dependencies: ["AtelierDiff", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strict),
        .testTarget(name: "AtelierSyntaxModelTests", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
        // Themes as values keyed by highlight role, with Xcode theme import; the apps bridge to their colour types.
        .target(name: "AtelierTheme", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
        .testTarget(
            name: "AtelierThemeTests", dependencies: ["AtelierTheme", "AtelierSyntaxModel"], swiftSettings: strict),
        .testTarget(name: "AtelierTextTests", dependencies: ["AtelierText"], swiftSettings: strict),
        .testTarget(name: "AtelierGrammarTests", dependencies: ["AtelierGrammar"], swiftSettings: strict),
        .testTarget(name: "AtelierParserTests", dependencies: ["AtelierParser"], swiftSettings: strict),
        .testTarget(name: "AtelierQueryTests", dependencies: ["AtelierQuery"], swiftSettings: strict),
        .testTarget(
            name: "AtelierSourcesTests",
            dependencies: [
                "AtelierSources", "AtelierGit", "AtelierProcess", "AtelierSyntaxModel",
                .product(name: "AemiRuntime", package: "aemi")
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
            swiftSettings: strict)
    ]
)
