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
        .library(name: "AtelierSwiftSyntax", targets: ["AtelierSwiftSyntax"])
    ],
    dependencies: [
        .package(url: "https://github.com/Aemi-Studio/aemi.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0")
    ],
    targets: [
        // The vocabulary highlighting is expressed in: languages, and later roles and tokens.
        .target(name: "AtelierSyntaxModel", swiftSettings: strict),
        // Line and intraline diffing, moved blocks, hunk layout and unified patches. Pure value code.
        .target(name: "AtelierDiff", dependencies: ["AtelierSyntaxModel"], swiftSettings: strict),
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
        .testTarget(name: "AtelierDiffTests", dependencies: ["AtelierDiff"], swiftSettings: strict),
        .testTarget(
            name: "AtelierLexersTests", dependencies: ["AtelierLexers", "AtelierSyntaxModel"], swiftSettings: strict),
        .testTarget(
            name: "AtelierSwiftSyntaxTests", dependencies: ["AtelierSwiftSyntax", "AtelierDiff", "AtelierSyntaxModel"],
            swiftSettings: strict)
    ]
)
