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
        // The public surface; `KittySearch`, an editor implementation detail, stays an internal target.
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
        .package(url: "https://github.com/g-cqd/TerminalKit.git", revision: "264f7448191b0d802db9f4a625a54d3d3064ddd7"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "5f0c47c56223db4401d7a67d7792b02fe0b5b322"),
        // AtelierCore's own pin, URL and revision alike: SwiftPM rejects one package identity at two locations or
        // versions in the same graph.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "a6c2d580b859cc595e602126d2ded79a672ce43c")
    ],
    targets: [
        // Layer 2d — File system browsing
        .target(
            name: "KittyFileTree",
            dependencies: [
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AtelierFileTree", package: "AtelierCore")
            ],
            swiftSettings: strict),

        // Layer 2e — SF Symbols discovery + terminal glyph helpers
        .target(
            name: "KittySymbols", dependencies: [.product(name: "AemiJSON", package: "AemiJSON")],
            swiftSettings: strict),

        // Layer 2f — Git integration (pluggable)
        .target(
            name: "KittyGit",
            dependencies: [
                "KittyFileTree", .product(name: "AtelierProcess", package: "AtelierCore"),
                .product(name: "AtelierGit", package: "AtelierCore"),
                .product(name: "AtelierDiff", package: "AtelierCore"),
                .product(name: "TerminalKitText", package: "TerminalKit")
            ],
            swiftSettings: strict),

        // Layer 2g — Search engine primitives
        .target(
            name: "KittySearch",
            dependencies: [.product(name: "AtelierSearch", package: "AtelierCore")],
            swiftSettings: strict),

        // Layers 3a–3c (grammar tables, GLR parser, queries) live in AtelierCore; text storage in TerminalKit.

        // Layer 3d — Themes + styled text producer
        .target(
            name: "KittySyntax",
            dependencies: [
                .product(name: "AtelierGrammar", package: "AtelierCore"),
                .product(name: "AtelierParser", package: "AtelierCore"),
                .product(name: "AtelierScanners", package: "AtelierCore"),
                .product(name: "AtelierQuery", package: "AtelierCore"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "AtelierSyntaxModel", package: "AtelierCore"),
                .product(name: "AtelierLexers", package: "AtelierCore"),
                .product(name: "AtelierTheme", package: "AtelierCore"),
                .product(name: "AtelierGrammarCorpus", package: "AtelierCore"),
                .product(name: "AemiCore", package: "aemi")
            ],
            swiftSettings: strict
        ),

        // Layer 4 — View protocol, layout, tree/text widgets
        .target(
            name: "KittyWidgets",
            dependencies: [
                "KittySyntax", .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit")
            ],
            swiftSettings: strict),

        // Layer 4b — Workspace domain: document, tab, file lifecycle, git coordination
        .target(
            name: "KittyWorkspace",
            dependencies: [
                .product(name: "TerminalKitText", package: "TerminalKit"), "KittySyntax", "KittyFileTree", "KittyGit",
                .product(name: "AemiCore", package: "aemi"), .product(name: "AemiIO", package: "aemi")
            ],
            swiftSettings: strict),

        // Layer 5 — App lifecycle, event loop, signals
        .target(
            name: "KittyApp",
            dependencies: [
                "KittyWidgets", .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "AemiCore", package: "aemi")
            ],
            swiftSettings: strict),

        // Layer 6 — Editor logic library: all but `AppMain`, so the tests depend on a library, not an executable
        .target(
            name: "KittyEditor",
            dependencies: [
                "KittyApp", "KittyWorkspace", .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "AtelierTheme", package: "AtelierCore"),
                "KittyFileTree",
                .product(name: "TerminalKitRender", package: "TerminalKit"), "KittySyntax", "KittySymbols", "KittyGit",
                "KittySearch",
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON")
            ],
            swiftSettings: strict),

        // KittyCode — The executable, a thin shell over `KittyEditor`: argv, config, runtime wiring, crash log
        .executableTarget(
            name: "KittyCode",
            dependencies: [
                "KittyEditor", "KittyApp", .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                "KittyFileTree", "KittyGit", .product(name: "TerminalKitRender", package: "TerminalKit"),
                "KittyWorkspace",
                .product(name: "AemiCore", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AtelierProcess", package: "AtelierCore")
            ], swiftSettings: strict),

        // KittySymbols CLI
        .executableTarget(
            name: "KittySymbolsCLI", dependencies: ["KittySymbols"],
            swiftSettings: strict),

        // Owning terminal suites are in TerminalKit; app integration tests remain here.
        .testTarget(
            name: "KittySyntaxTests",
            dependencies: [
                "KittySyntax", .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "AtelierSyntaxModel", package: "AtelierCore"),
                .product(name: "AtelierGrammarCorpus", package: "AtelierCore"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittyWidgetsTests",
            dependencies: [
                "KittyWidgets",
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittyAppTests",
            dependencies: [
                "KittyApp", .product(name: "AemiTesting", package: "aemi"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittyCodeTests",
            dependencies: [
                "KittyEditor", "KittyFileTree", "KittyWorkspace",
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "AemiTesting", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittySymbolsTests", dependencies: ["KittySymbols"],
            swiftSettings: strict),
        .testTarget(
            name: "KittyWorkspaceTests",
            dependencies: [
                "KittyWorkspace", "KittySyntax", .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "AtelierFileTree", package: "AtelierCore"),
                .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiTesting", package: "aemi")
            ],
            swiftSettings: strict),
        .testTarget(
            name: "KittyGitTests",
            dependencies: [
                "KittyGit", .product(name: "AtelierProcess", package: "AtelierCore"),
                .product(name: "AtelierTestSupport", package: "AtelierCore"),
                .product(name: "AtelierFileTree", package: "AtelierCore"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict)
    ]
)
