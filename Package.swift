// swift-tools-version: 6.2

import PackageDescription

let defaultSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency")
]

let package = Package(
    name: "KittyTUI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "KittyTerminal", targets: ["KittyTerminal"]),
        .library(name: "KittyCodecs", targets: ["KittyCodecs"]),
        .library(name: "KittyInput", targets: ["KittyInput"]),
        .library(name: "KittyRenderer", targets: ["KittyRenderer"]),
        .library(name: "KittyGrammar", targets: ["KittyGrammar"]),
        .library(name: "KittyParser", targets: ["KittyParser"]),
        .library(name: "KittyQuery", targets: ["KittyQuery"]),
        .library(name: "KittySyntax", targets: ["KittySyntax"]),
        .library(name: "KittyWidgets", targets: ["KittyWidgets"]),
        .library(name: "KittyApp", targets: ["KittyApp"]),
        .library(name: "KittyText", targets: ["KittyText"]),
        .library(name: "KittyFileTree", targets: ["KittyFileTree"]),
        .library(name: "KittySymbols", targets: ["KittySymbols"]),
        .library(name: "KittyGit", targets: ["KittyGit"]),
        .library(name: "KittyWorkspace", targets: ["KittyWorkspace"]),
        .executable(name: "KittyCode", targets: ["KittyCode"]),
        .executable(name: "KittySymbolsCLI", targets: ["KittySymbolsCLI"]),
    ],
    targets: [
        .target(name: "KittySync", swiftSettings: defaultSwiftSettings),

        // Layer 0 — Raw mode, FD I/O, terminal queries
        .target(
            name: "KittyTerminal", dependencies: ["KittySync"], swiftSettings: defaultSwiftSettings),

        // Layer 1 — Escape sequence encoders/decoders
        .target(
            name: "KittyCodecs", dependencies: ["KittyTerminal"],
            swiftSettings: defaultSwiftSettings),

        // Layer 2a — Async InputEvent stream
        .target(
            name: "KittyInput", dependencies: ["KittyCodecs"], swiftSettings: defaultSwiftSettings),

        // Layer 2b — Screen buffer, diff renderer
        .target(
            name: "KittyRenderer", dependencies: ["KittyCodecs", "KittyText"],
            swiftSettings: defaultSwiftSettings),

        // Layer 2c — Text buffer primitives
        .target(name: "KittyText", swiftSettings: defaultSwiftSettings),

        // Layer 2d — File system browsing
        .target(
            name: "KittyFileTree", dependencies: ["KittySync"], swiftSettings: defaultSwiftSettings),

        // Layer 2e — SF Symbols discovery + terminal glyph helpers
        .target(name: "KittySymbols", swiftSettings: defaultSwiftSettings),

        // Layer 2f — Git integration (pluggable)
        .target(
            name: "KittyGit", dependencies: ["KittyFileTree", "KittySync"],
            swiftSettings: defaultSwiftSettings),

        // Layer 3a — grammar.json loader + LR table compiler
        .target(name: "KittyGrammar", swiftSettings: defaultSwiftSettings),

        // Layer 3b — GLR incremental parser engine
        .target(
            name: "KittyParser", dependencies: ["KittyGrammar", "KittySync"],
            swiftSettings: defaultSwiftSettings),

        // Layer 3c — .scm query parser + pattern matcher
        .target(
            name: "KittyQuery", dependencies: ["KittyParser", "KittySync"],
            swiftSettings: defaultSwiftSettings),

        // Layer 3d — Themes + styled text producer
        .target(
            name: "KittySyntax",
            dependencies: [
                "KittyGrammar", "KittyParser", "KittyQuery", "KittyRenderer", "KittySync",
            ],
            resources: [.copy("Grammars")],
            swiftSettings: defaultSwiftSettings
        ),

        // Layer 4 — View protocol, layout, tree/text widgets
        .target(
            name: "KittyWidgets", dependencies: ["KittySyntax", "KittyInput"],
            swiftSettings: defaultSwiftSettings),

        // Layer 4b — Workspace domain: document, tab, file lifecycle, git coordination
        .target(
            name: "KittyWorkspace",
            dependencies: ["KittyText", "KittySyntax", "KittyFileTree", "KittyGit", "KittySync"],
            swiftSettings: defaultSwiftSettings),

        // Layer 5 — App lifecycle, event loop, signals
        .target(
            name: "KittyApp", dependencies: ["KittyWidgets", "KittyInput", "KittySync"],
            swiftSettings: defaultSwiftSettings),

        // KittyCode — Terminal code editor
        .executableTarget(
            name: "KittyCode",
            dependencies: [
                "KittyApp", "KittyWorkspace", "KittyInput", "KittyText", "KittyFileTree",
                "KittySyntax", "KittySymbols", "KittyGit",
            ], swiftSettings: defaultSwiftSettings),

        // KittySymbols CLI
        .executableTarget(
            name: "KittySymbolsCLI", dependencies: ["KittySymbols"],
            swiftSettings: defaultSwiftSettings),

        // Tests
        .testTarget(
            name: "KittyTerminalTests", dependencies: ["KittyTerminal"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyCodecsTests", dependencies: ["KittyCodecs"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyInputTests", dependencies: ["KittyInput"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyRendererTests", dependencies: ["KittyRenderer", "KittyTerminal"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyGrammarTests", dependencies: ["KittyGrammar"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyParserTests", dependencies: ["KittyParser"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyQueryTests", dependencies: ["KittyQuery"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittySyntaxTests", dependencies: ["KittySyntax"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyWidgetsTests", dependencies: ["KittyWidgets"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyAppTests", dependencies: ["KittyApp"], swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyCodeTests", dependencies: ["KittyCode", "KittyFileTree", "KittyWorkspace"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyTextTests", dependencies: ["KittyText"], swiftSettings: defaultSwiftSettings
        ),
        .testTarget(
            name: "KittyFileTreeTests", dependencies: ["KittyFileTree"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittySymbolsTests", dependencies: ["KittySymbols"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyWorkspaceTests", dependencies: ["KittyWorkspace"],
            swiftSettings: defaultSwiftSettings),
        .testTarget(
            name: "KittyGitTests", dependencies: ["KittyGit"], swiftSettings: defaultSwiftSettings),
    ]
)
