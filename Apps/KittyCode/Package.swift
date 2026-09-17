// swift-tools-version: 6.4

import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "KittyTUI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Library products = modules an external SPM package can depend on
        // by listing this package as a dependency. The list below is the
        // intentional public surface; `KittyParser` and `KittySearch` are
        // implementation details of the editor (only `KittyCode`
        // consumes them) and are deliberately NOT promoted to products.
        // Their internal targets still exist below; only the product
        // declaration is dropped. Audit B5.
        .library(name: "KittyTerminal", targets: ["KittyTerminal"]),
        .library(name: "KittyStyle", targets: ["KittyStyle"]),
        .library(name: "KittyCodecs", targets: ["KittyCodecs"]),
        .library(name: "KittyInput", targets: ["KittyInput"]),
        .library(name: "KittyRenderer", targets: ["KittyRenderer"]),
        .library(name: "KittySyntax", targets: ["KittySyntax"]),
        .library(name: "KittyWidgets", targets: ["KittyWidgets"]),
        .library(name: "KittyApp", targets: ["KittyApp"]),
        .library(name: "KittyFileTree", targets: ["KittyFileTree"]),
        .library(name: "KittySymbols", targets: ["KittySymbols"]),
        .library(name: "KittyGit", targets: ["KittyGit"]),
        .library(name: "KittyWorkspace", targets: ["KittyWorkspace"]),
        .library(name: "KittyEditor", targets: ["KittyEditor"]),
        .executable(name: "KittyCode", targets: ["KittyCode"]),
        .executable(name: "KittySymbolsCLI", targets: ["KittySymbolsCLI"])
    ],
    dependencies: [
        .package(path: "../../Packages/AtelierCore"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", branch: "main")
    ],
    targets: [
        // Layer 0 — Raw mode, FD I/O, terminal queries
        .target(name: "KittyTerminal", swiftSettings: strict),

        // Layer 0b — Pure visual-style value types (Color, UnderlineStyle,
        // Style). No dependencies. KittySyntax depends on this directly
        // so it doesn't transitively pull in the terminal-codec layer
        // just to reference `Style`. Audit D2.
        .target(name: "KittyStyle", swiftSettings: strict),

        // Layer 1 — Escape sequence encoders/decoders
        .target(
            name: "KittyCodecs",
            dependencies: ["KittyTerminal", "KittyStyle", .product(name: "AemiKernel", package: "aemi")],
            swiftSettings: strict),

        // Layer 2a — Async InputEvent stream
        .target(
            name: "KittyInput", dependencies: ["KittyCodecs", .product(name: "AemiKernel", package: "aemi")],
            swiftSettings: strict),

        // Layer 2b — Screen buffer, diff renderer
        .target(
            name: "KittyRenderer",
            dependencies: ["KittyCodecs", .product(name: "AtelierText", package: "AtelierCore"), "KittyStyle"],
            swiftSettings: strict),

        // Layer 2c — Text buffer primitives

        // Layer 2d — File system browsing
        .target(
            name: "KittyFileTree",
            dependencies: [
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AtelierFileTree", package: "AtelierCore")
            ],
            swiftSettings: strict),

        // Layer 2e — SF Symbols discovery + terminal glyph helpers
        .target(name: "KittySymbols", swiftSettings: strict),

        // Layer 2f — Git integration (pluggable)
        .target(
            name: "KittyGit",
            dependencies: [
                "KittyFileTree", .product(name: "AtelierProcess", package: "AtelierCore"),
                .product(name: "AtelierGit", package: "AtelierCore"),
                .product(name: "AtelierDiff", package: "AtelierCore")
            ],
            swiftSettings: strict),

        // Layer 2g — Search engine primitives
        .target(
            name: "KittySearch",
            dependencies: [.product(name: "AtelierSearch", package: "AtelierCore")],
            swiftSettings: strict),

        // Layers 3a–3c (grammar tables, GLR parser, queries) and 2c (text storage) live in AtelierCore.

        // Layer 3d — Themes + styled text producer
        .target(
            name: "KittySyntax",
            dependencies: [
                .product(name: "AtelierGrammar", package: "AtelierCore"),
                .product(name: "AtelierParser", package: "AtelierCore"),
                .product(name: "AtelierQuery", package: "AtelierCore"), "KittyStyle",
                .product(name: "AtelierSyntaxModel", package: "AtelierCore"),
                .product(name: "AtelierLexers", package: "AtelierCore"),
                .product(name: "AtelierTheme", package: "AtelierCore"),
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AemiKernel", package: "aemi")
            ],
            resources: [.copy("Grammars")],
            swiftSettings: strict
        ),

        // Layer 4 — View protocol, layout, tree/text widgets.
        // Direct dep on `KittyRenderer` (was previously transitive via
        // `KittySyntax` before audit D2 cleaned up that layering reach).
        .target(
            name: "KittyWidgets", dependencies: ["KittySyntax", "KittyInput", "KittyRenderer"],
            swiftSettings: strict),

        // Layer 4b — Workspace domain: document, tab, file lifecycle, git coordination
        .target(
            name: "KittyWorkspace",
            dependencies: [
                .product(name: "AtelierText", package: "AtelierCore"), "KittySyntax", "KittyFileTree", "KittyGit",
                .product(name: "AemiCore", package: "aemi")
            ],
            swiftSettings: strict),

        // Layer 5 — App lifecycle, event loop, signals
        .target(
            name: "KittyApp",
            dependencies: ["KittyWidgets", "KittyInput", .product(name: "AemiCore", package: "aemi")],
            swiftSettings: strict),

        // Layer 6 — Editor logic library. Holds every editor file except
        // the executable shell (`AppMain`, `CLIArguments`, `Version`). The
        // split lets `KittyCodeTests` depend on a library rather than the
        // executable target (fragile across SPM versions) and creates a
        // clean seam for future platform shells (SwiftUI wrapper, XPC
        // service, headless mode). Audit D3.
        .target(
            name: "KittyEditor",
            dependencies: [
                "KittyApp", "KittyWorkspace", "KittyInput", .product(name: "AtelierText", package: "AtelierCore"),
                .product(name: "AtelierTheme", package: "AtelierCore"),
                "KittyFileTree",
                "KittyRenderer", "KittySyntax", "KittySymbols", "KittyGit", "KittySearch",
                "KittyStyle", "KittyTerminal",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict),

        // KittyCode — Terminal code editor executable. Thin shell over
        // `KittyEditor`: parses argv via `KittyEditor.CLIArguments`,
        // loads config, applies launch overrides, wires the runtime,
        // writes a crash log on uncaught error.
        .executableTarget(
            name: "KittyCode",
            dependencies: [
                "KittyEditor", "KittyApp", "KittyTerminal", "KittyCodecs",
                "KittyFileTree", "KittyGit", "KittyRenderer", "KittyWorkspace",
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AtelierProcess", package: "AtelierCore")
            ], swiftSettings: strict),

        // KittySymbols CLI
        .executableTarget(
            name: "KittySymbolsCLI", dependencies: ["KittySymbols"],
            swiftSettings: strict),

        // Tests
        .testTarget(
            name: "KittyTerminalTests", dependencies: ["KittyTerminal"],
            swiftSettings: strict),
        .testTarget(
            name: "KittyCodecsTests", dependencies: ["KittyCodecs"],
            swiftSettings: strict),
        .testTarget(
            name: "KittyInputTests", dependencies: ["KittyInput"],
            swiftSettings: strict),
        .testTarget(
            name: "KittyRendererTests", dependencies: ["KittyRenderer", "KittyTerminal"],
            swiftSettings: strict),
        .testTarget(
            name: "KittySyntaxTests",
            dependencies: [
                "KittySyntax", "KittyCodecs", .product(name: "AtelierSyntaxModel", package: "AtelierCore"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittyWidgetsTests", dependencies: ["KittyWidgets"],
            swiftSettings: strict),
        .testTarget(
            name: "KittyAppTests",
            dependencies: ["KittyApp", .product(name: "AemiTesting", package: "aemi")],
            swiftSettings: strict),
        .testTarget(
            name: "KittyCodeTests",
            dependencies: [
                "KittyEditor", "KittyFileTree", "KittyWorkspace", .product(name: "AemiTesting", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittySymbolsTests", dependencies: ["KittySymbols"],
            swiftSettings: strict),
        .testTarget(
            name: "KittyWorkspaceTests",
            dependencies: ["KittyWorkspace", .product(name: "AemiTesting", package: "aemi")],
            swiftSettings: strict),
        .testTarget(
            name: "KittyGitTests",
            dependencies: [
                "KittyGit", .product(name: "AtelierProcess", package: "AtelierCore"),
                .product(name: "AtelierTestSupport", package: "AtelierCore"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict)
    ]
)
