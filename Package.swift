// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KittyTUI",
    platforms: [
        .macOS(.v14),
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
        .executable(name: "Demo", targets: ["Demo"]),
        .executable(name: "KittyCode", targets: ["KittyCode"]),
    ],
    targets: [
        // Layer 0 — Raw mode, FD I/O, terminal queries
        .target(name: "KittyTerminal"),

        // Layer 1 — Escape sequence encoders/decoders
        .target(name: "KittyCodecs", dependencies: ["KittyTerminal"]),

        // Layer 2a — Async InputEvent stream
        .target(name: "KittyInput", dependencies: ["KittyCodecs"]),

        // Layer 2b — Screen buffer, diff renderer
        .target(name: "KittyRenderer", dependencies: ["KittyCodecs"]),

        // Layer 3a — grammar.json loader + LR table compiler
        .target(name: "KittyGrammar"),

        // Layer 3b — GLR incremental parser engine
        .target(name: "KittyParser", dependencies: ["KittyGrammar"]),

        // Layer 3c — .scm query parser + pattern matcher
        .target(name: "KittyQuery", dependencies: ["KittyParser"]),

        // Layer 3d — Themes + styled text producer
        .target(
            name: "KittySyntax",
            dependencies: ["KittyQuery", "KittyRenderer"],
            resources: [.copy("Grammars")]
        ),

        // Layer 4 — View protocol, layout, tree/text widgets
        .target(name: "KittyWidgets", dependencies: ["KittySyntax", "KittyInput"]),

        // Layer 5 — App lifecycle, event loop, signals
        .target(name: "KittyApp", dependencies: ["KittyWidgets"]),

        // Demo executable
        .executableTarget(name: "Demo", dependencies: ["KittyApp"], path: "Demo"),

        // KittyCode — Terminal code editor
        .executableTarget(name: "KittyCode", dependencies: ["KittyApp"]),

        // Tests
        .testTarget(name: "KittyTerminalTests", dependencies: ["KittyTerminal"]),
        .testTarget(name: "KittyCodecsTests", dependencies: ["KittyCodecs"]),
        .testTarget(name: "KittyInputTests", dependencies: ["KittyInput"]),
        .testTarget(name: "KittyRendererTests", dependencies: ["KittyRenderer", "KittyTerminal"]),
        .testTarget(name: "KittyGrammarTests", dependencies: ["KittyGrammar"]),
        .testTarget(name: "KittyParserTests", dependencies: ["KittyParser"]),
        .testTarget(name: "KittyQueryTests", dependencies: ["KittyQuery"]),
        .testTarget(name: "KittySyntaxTests", dependencies: ["KittySyntax"]),
        .testTarget(name: "KittyWidgetsTests", dependencies: ["KittyWidgets"]),
        .testTarget(name: "KittyAppTests", dependencies: ["KittyApp"]),
    ]
)
